//! Cycle de vie complet, puis les attaques que le protocole doit refuser.

use agent_only_core::*;
use alloy_primitives::{Address, B256, U256};
use k256::ecdsa::SigningKey;

const NOW: u64 = 1_000;
const FAR: u64 = 1_000_000;

fn key(n: u8) -> SigningKey {
    SigningKey::from_slice(&[n; 32]).unwrap()
}
fn addr(k: &SigningKey) -> Address {
    address_of(k.verifying_key())
}
fn sponsor(n: u8) -> Address {
    Address::from([n; 20])
}

/// Deux agents enroles (1 et 2), chacun avec 1 000 USDC au coffre.
fn world() -> (Ledger, SigningKey, SigningKey) {
    let mut l = Ledger::new(8453, Address::from([0xAA; 20]));
    let (k1, k2) = (key(1), key(2));
    l.enroll(1, addr(&k1), sponsor(101), true).unwrap();
    l.enroll(2, addr(&k2), sponsor(102), true).unwrap();
    l.deposit(1, 1_000).unwrap();
    l.deposit(2, 1_000).unwrap();
    (l, k1, k2)
}

fn signed(l: &Ledger, k: &SigningKey, terms: Terms, token: u64, agent: u64, cp: u64) -> SignedIntent {
    let nonce = if terms.op() == Op::Mint {
        l.mint_nonce(agent)
    } else {
        l.token(token).map(|t| t.nonce).unwrap_or(0)
    };
    signed_with(l, k, terms, token, agent, cp, nonce, FAR)
}

#[allow(clippy::too_many_arguments)]
fn signed_with(
    l: &Ledger,
    k: &SigningKey,
    terms: Terms,
    token: u64,
    agent: u64,
    cp: u64,
    nonce: u64,
    deadline: u64,
) -> SignedIntent {
    let intent = Intent {
        op: terms.op() as u8,
        tokenId: U256::from(token),
        agentId: U256::from(agent),
        counterparty: U256::from(cp),
        termsHash: terms.hash(),
        tokenNonce: U256::from(nonce),
        deadline,
    };
    let sig = sign(k, l.digest(&intent));
    SignedIntent { intent, sig }
}

fn mint(l: &mut Ledger, k: &SigningKey, agent: u64) -> u64 {
    let terms = Terms::Mint { content: B256::from([7; 32]) };
    let s = signed(l, k, terms, 0, agent, 0);
    l.execute(0, terms, &[s], NOW).unwrap()
}

#[test]
fn cycle_de_vie_complet() {
    let (mut l, k1, k2) = world();
    let id = mint(&mut l, &k1, 1);
    assert_eq!(l.token(id).unwrap().agent, 1);

    // Transfert cosigne 1 -> 2.
    let t = Terms::Transfer;
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    l.execute(id, t, &s, NOW).unwrap();
    assert_eq!(l.token(id).unwrap().agent, 2);

    // Vente 2 -> 1 contre 300 : NFT et USDC bougent ensemble.
    let t = Terms::Swap { price: 300 };
    let s = [signed(&l, &k2, t, id, 2, 1), signed(&l, &k1, t, id, 1, 2)];
    l.execute(id, t, &s, NOW).unwrap();
    assert_eq!((l.token(id).unwrap().agent, l.balance(1), l.balance(2)), (1, 700, 1_300));

    // Staking sur place, puis sortie apres l'echeance.
    let t = Terms::Stake { until: NOW + 100 };
    l.execute(id, t, &[signed(&l, &k1, t, id, 1, 0)], NOW).unwrap();
    assert_eq!(l.token(id).unwrap().state, State::Staked);
    let t = Terms::Unstake;
    let s = signed(&l, &k1, t, id, 1, 0);
    assert_eq!(l.execute(id, t, &[s.clone()], NOW + 50), Err(Error::Locked));
    l.execute(id, t, &[s], NOW + 100).unwrap();

    // Location a l'agent 2 : le detenteur ne change pas, le droit s'eteint seul.
    let t = Terms::Rent { price: 50, expires: NOW + 300 };
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    l.execute(id, t, &s, NOW + 100).unwrap();
    let tok = *l.token(id).unwrap();
    assert_eq!((tok.agent, tok.state, tok.renter), (1, State::Rented, Some((2, NOW + 300))));

    // Pret sur gage apres la fin de la location, rembourse a temps.
    let t = Terms::Pledge { principal: 400, repay: 440, due: NOW + 900 };
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    l.execute(id, t, &s, NOW + 300).unwrap();
    assert_eq!(l.token(id).unwrap().state, State::Pledged);
    let t = Terms::Repay;
    l.execute(id, t, &[signed(&l, &k1, t, id, 1, 0)], NOW + 800).unwrap();
    assert_eq!(l.token(id).unwrap().state, State::Free);

    // Second pret, defaut : le preteur recupere le token.
    let t = Terms::Pledge { principal: 100, repay: 110, due: NOW + 1_000 };
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    l.execute(id, t, &s, NOW + 900).unwrap();
    let t = Terms::Claim;
    let s = signed(&l, &k2, t, id, 2, 0);
    assert_eq!(l.execute(id, t, &[s.clone()], NOW + 1_000), Err(Error::NotDue));
    l.execute(id, t, &[s], NOW + 1_001).unwrap();
    assert_eq!(l.token(id).unwrap().agent, 2);

    // Burn par le detenteur. L'argent n'a ete ni cree ni detruit.
    let t = Terms::Burn;
    l.execute(id, t, &[signed(&l, &k2, t, id, 2, 0)], NOW + 1_100).unwrap();
    assert!(l.token(id).is_none());
    assert_eq!(l.vault_total(), 2_000);
}

#[test]
fn un_wallet_humain_ne_peut_rien_signer() {
    let (mut l, k1, k2) = world();
    let id = mint(&mut l, &k1, 1);
    let human = key(9);

    // L'humain signe a la place de l'agent 1.
    let t = Terms::Transfer;
    let s = [signed(&l, &human, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    assert_eq!(l.execute(id, t, &s, NOW), Err(Error::BadSigner));

    // L'humain se presente comme destinataire sous un identifiant non enrole.
    let s = [signed(&l, &k1, t, id, 1, 9), signed(&l, &human, t, id, 9, 1)];
    assert_eq!(l.execute(id, t, &s, NOW), Err(Error::UnknownAgent));

    // Sans attestation valide, pas d'enrolement.
    assert_eq!(l.enroll(9, addr(&human), sponsor(9), false), Err(Error::BadAttestation));
    assert_eq!(l.token(id).unwrap().agent, 1);
}

#[test]
fn rejeu_d_un_mint_refuse() {
    let (mut l, k1, _k2) = world();
    let terms = Terms::Mint { content: B256::from([7; 32]) };
    let s = signed(&l, &k1, terms, 0, 1, 0);
    l.execute(0, terms, &[s.clone()], NOW).unwrap();
    // Le meme paquet ne cree pas un second token.
    assert_eq!(l.execute(0, terms, &[s], NOW), Err(Error::BadNonce));
    assert_eq!(l.tokens().count(), 1);
}

#[test]
fn aucun_nft_non_sollicite() {
    let (mut l, k1, _k2) = world();
    let id = mint(&mut l, &k1, 1);
    let t = Terms::Transfer;
    // L'emetteur seul ne suffit pas : le destinataire doit cosigner.
    let s = [signed(&l, &k1, t, id, 1, 2)];
    assert_eq!(l.execute(id, t, &s, NOW), Err(Error::BadParties));
}

#[test]
fn rejeu_et_modification_par_le_relais() {
    let (mut l, k1, k2) = world();
    let id = mint(&mut l, &k1, 1);

    let t = Terms::Swap { price: 100 };
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];

    // Le relais change le prix : l'empreinte des termes ne correspond plus.
    assert_eq!(
        l.execute(id, Terms::Swap { price: 1 }, &s, NOW),
        Err(Error::TermsMismatch)
    );
    // Le relais change le destinataire dans une intention : signature invalide.
    let mut forged = s.clone();
    forged[0].intent.counterparty = U256::from(3);
    assert_eq!(l.execute(id, t, &forged, NOW), Err(Error::BadSigner));

    // La vente passe, puis le meme paquet est rejoue.
    l.execute(id, t, &s, NOW).unwrap();
    assert_eq!(l.execute(id, t, &s, NOW), Err(Error::BadNonce));

    // Une intention echue est refusee.
    let t = Terms::Burn;
    let nonce = l.token(id).unwrap().nonce;
    let old = signed_with(&l, &k2, t, id, 2, 0, nonce, NOW - 1);
    assert_eq!(l.execute(id, t, &[old], NOW), Err(Error::Expired));
}

#[test]
fn etats_exclusifs() {
    let (mut l, k1, k2) = world();
    let id = mint(&mut l, &k1, 1);
    let t = Terms::Stake { until: NOW + 500 };
    l.execute(id, t, &[signed(&l, &k1, t, id, 1, 0)], NOW).unwrap();

    for t in [
        Terms::Transfer,
        Terms::Swap { price: 10 },
        Terms::Rent { price: 1, expires: NOW + 50 },
        Terms::Pledge { principal: 1, repay: 2, due: NOW + 50 },
    ] {
        let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
        assert_eq!(l.execute(id, t, &s, NOW + 1), Err(Error::BadState));
    }
    let t = Terms::Burn;
    assert_eq!(
        l.execute(id, t, &[signed(&l, &k1, t, id, 1, 0)], NOW + 1),
        Err(Error::BadState)
    );
}

#[test]
fn ancienne_cle_de_session_refusee_apres_reenrolement() {
    let (mut l, k1, _k2) = world();
    let id = mint(&mut l, &k1, 1);

    // L'enclave redemarre : nouvelle cle ephemere, meme agent, meme sponsor.
    let k1b = key(11);
    l.enroll(1, addr(&k1b), sponsor(101), true).unwrap();

    let t = Terms::Burn;
    assert_eq!(
        l.execute(id, t, &[signed(&l, &k1, t, id, 1, 0)], NOW),
        Err(Error::BadSigner)
    );
    // Le token est toujours la : il est rattache a l'agent, pas a la cle.
    assert_eq!(l.token(id).unwrap().agent, 1);
    l.execute(id, t, &[signed(&l, &k1b, t, id, 1, 0)], NOW).unwrap();

    // Un autre sponsor ne peut pas reprendre l'agent.
    assert_eq!(l.enroll(1, addr(&key(12)), sponsor(66), true), Err(Error::NotSponsor));
}

#[test]
fn pouvoirs_du_sponsor_limites() {
    let (mut l, k1, k2) = world();
    let id = mint(&mut l, &k1, 1);

    // Il retire des USDC ; un tiers ne le peut pas.
    assert_eq!(l.withdraw(sponsor(66), 1, 10), Err(Error::NotSponsor));
    l.withdraw(sponsor(101), 1, 10).unwrap();
    assert_eq!(l.balance(1), 990);

    // Il gele son agent : plus aucune operation, le token ne bouge pas.
    l.set_frozen(sponsor(101), 1, true).unwrap();
    let t = Terms::Transfer;
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    assert_eq!(l.execute(id, t, &s, NOW), Err(Error::Frozen));
    assert_eq!(l.token(id).unwrap().agent, 1);
}

#[test]
fn paiement_impossible_rien_ne_bouge() {
    let (mut l, k1, k2) = world();
    let id = mint(&mut l, &k1, 1);
    let before = *l.token(id).unwrap();

    let t = Terms::Swap { price: 5_000 };
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    assert_eq!(l.execute(id, t, &s, NOW), Err(Error::InsufficientFunds));
    assert_eq!(*l.token(id).unwrap(), before);
    assert_eq!((l.balance(1), l.balance(2)), (1_000, 1_000));
}

#[test]
fn seul_le_preteur_saisit_et_seulement_apres_echeance() {
    let (mut l, k1, k2) = world();
    let id = mint(&mut l, &k1, 1);
    let t = Terms::Pledge { principal: 200, repay: 220, due: NOW + 100 };
    let s = [signed(&l, &k1, t, id, 1, 2), signed(&l, &k2, t, id, 2, 1)];
    l.execute(id, t, &s, NOW).unwrap();

    let t = Terms::Claim;
    // L'emprunteur ne peut pas « saisir » son propre gage.
    assert_eq!(
        l.execute(id, t, &[signed(&l, &k1, t, id, 1, 0)], NOW + 500),
        Err(Error::NotLender)
    );
    // Le preteur est gele apres l'echeance : il ne peut plus saisir.
    l.set_frozen(sponsor(102), 2, true).unwrap();
    assert_eq!(
        l.execute(id, t, &[signed(&l, &k2, t, id, 2, 0)], NOW + 500),
        Err(Error::Frozen)
    );
    // Le token n'est pas bloque : l'emprunteur peut encore rembourser.
    let r = Terms::Repay;
    l.execute(id, r, &[signed(&l, &k1, r, id, 1, 0)], NOW + 500).unwrap();
    assert_eq!(l.token(id).unwrap().state, State::Free);
    assert_eq!((l.balance(1), l.balance(2)), (980, 1_020));
    // Une fois rembourse, plus rien a saisir.
    l.set_frozen(sponsor(102), 2, false).unwrap();
    assert_eq!(
        l.execute(id, t, &[signed(&l, &k2, t, id, 2, 0)], NOW + 600),
        Err(Error::BadState)
    );
}

/// 20 000 operations tirees au hasard, valides ou non. Apres chacune :
/// le detenteur est un agent enrole, l'etat est coherent, le coffre est conserve.
#[test]
fn invariants_sous_operations_aleatoires() {
    let mut l = Ledger::new(8453, Address::from([0xAA; 20]));
    let keys: Vec<SigningKey> = (1..=4).map(key).collect();
    for (i, k) in keys.iter().enumerate() {
        let id = i as u64 + 1;
        l.enroll(id, addr(k), sponsor(100 + id as u8), true).unwrap();
        l.deposit(id, 10_000).unwrap();
    }
    let total = l.vault_total();

    let mut seed: u64 = 0x9E37_79B9_7F4A_7C15;
    let mut rnd = move |n: u64| {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        seed % n
    };

    let mut now = NOW;
    let mut ok = 0u32;
    for _ in 0..20_000 {
        now += rnd(40);
        let a = rnd(5) + 1; // 5 = identifiant jamais enrole
        let b = rnd(5) + 1;
        let token = rnd(12);
        let amount = rnd(3_000) as u128;
        let terms = match rnd(10) {
            0 => Terms::Mint { content: B256::from([rnd(255) as u8; 32]) },
            1 => Terms::Transfer,
            2 => Terms::Swap { price: amount },
            3 => Terms::Stake { until: now + rnd(200) },
            4 => Terms::Unstake,
            5 => Terms::Rent { price: amount, expires: now + rnd(200) },
            6 => Terms::Pledge { principal: amount, repay: amount + 10, due: now + rnd(200) },
            7 => Terms::Repay,
            8 => Terms::Claim,
            _ => Terms::Burn,
        };
        let two = matches!(terms.op(), Op::Transfer | Op::Swap | Op::Rent | Op::Pledge);
        let tid = if terms.op() == Op::Mint { 0 } else { token };
        let ka = &keys[((a - 1) % 4) as usize];
        let kb = &keys[((b - 1) % 4) as usize];
        let pkg = if two {
            vec![signed(&l, ka, terms, tid, a, b), signed(&l, kb, terms, tid, b, a)]
        } else {
            vec![signed(&l, ka, terms, tid, a, 0)]
        };
        if l.execute(tid, terms, &pkg, now).is_ok() {
            ok += 1;
        }

        assert_eq!(l.vault_total(), total, "le coffre doit etre conserve");
        for (_, t) in l.tokens() {
            assert!(l.agent(t.agent).is_some(), "detenteur non enrole");
            assert_eq!(t.state == State::Pledged, t.lien.is_some());
            assert_eq!(t.state == State::Rented, t.renter.is_some());
            if let Some(lien) = t.lien {
                assert!(l.agent(lien.lender).is_some());
            }
        }
    }
    assert!(ok > 500, "trop peu d'operations valides pour que le test ait un sens : {ok}");
}
