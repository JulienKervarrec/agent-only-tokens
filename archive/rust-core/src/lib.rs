//! Specification executable du profil « Agent-Only Tokens ».
//!
//! Ce crate modelise en Rust pur ce que le contrat devra imposer :
//! - toute ecriture passe par des intentions EIP-712 signees par la cle de
//!   session d'un agent enrole ;
//! - un token n'a qu'un etat a la fois (libre, en staking, loue, gage) ;
//! - les paiements se reglent dans un coffre, dans la meme operation.
//!
//! Il ne verifie PAS d'attestation materielle : l'enrolement recoit un booleen
//! `attestation_valid` qui tient la place du verificateur on-chain.

use alloy_primitives::{keccak256, Address, B256, U256};
use alloy_sol_types::{eip712_domain, sol, Eip712Domain, SolStruct};
use k256::ecdsa::{RecoveryId, Signature, SigningKey, VerifyingKey};
use std::collections::BTreeMap;

sol! {
    /// Meme structure que dans le brouillon d'EIP.
    #[derive(Debug, PartialEq, Eq)]
    struct Intent {
        uint8 op;
        uint256 tokenId;
        uint256 agentId;
        uint256 counterparty;
        bytes32 termsHash;
        uint256 tokenNonce;
        uint64 deadline;
    }
}

#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Op {
    Mint = 0,
    Transfer,
    Swap,
    Stake,
    Unstake,
    Rent,
    Pledge,
    Repay,
    Claim,
    Burn,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Free,
    Staked,
    Rented,
    Pledged,
}

/// Termes d'une operation. Leur empreinte est signee par chaque partie.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Terms {
    Mint { content: B256 },
    Transfer,
    Swap { price: u128 },
    Stake { until: u64 },
    Unstake,
    Rent { price: u128, expires: u64 },
    Pledge { principal: u128, repay: u128, due: u64 },
    Repay,
    Claim,
    Burn,
}

impl Terms {
    pub fn op(&self) -> Op {
        match self {
            Terms::Mint { .. } => Op::Mint,
            Terms::Transfer => Op::Transfer,
            Terms::Swap { .. } => Op::Swap,
            Terms::Stake { .. } => Op::Stake,
            Terms::Unstake => Op::Unstake,
            Terms::Rent { .. } => Op::Rent,
            Terms::Pledge { .. } => Op::Pledge,
            Terms::Repay => Op::Repay,
            Terms::Claim => Op::Claim,
            Terms::Burn => Op::Burn,
        }
    }

    pub fn hash(&self) -> B256 {
        let mut b = vec![self.op() as u8];
        match self {
            Terms::Mint { content } => b.extend_from_slice(content.as_slice()),
            Terms::Swap { price } => b.extend_from_slice(&price.to_be_bytes()),
            Terms::Stake { until } => b.extend_from_slice(&until.to_be_bytes()),
            Terms::Rent { price, expires } => {
                b.extend_from_slice(&price.to_be_bytes());
                b.extend_from_slice(&expires.to_be_bytes());
            }
            Terms::Pledge { principal, repay, due } => {
                b.extend_from_slice(&principal.to_be_bytes());
                b.extend_from_slice(&repay.to_be_bytes());
                b.extend_from_slice(&due.to_be_bytes());
            }
            Terms::Transfer | Terms::Unstake | Terms::Repay | Terms::Claim | Terms::Burn => {}
        }
        keccak256(&b)
    }
}

#[derive(Clone, Debug)]
pub struct SignedIntent {
    pub intent: Intent,
    pub sig: [u8; 65],
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    BadAttestation,
    NoToken,
    BadOp,
    BadToken,
    TermsMismatch,
    BadNonce,
    Expired,
    UnknownAgent,
    Frozen,
    BadSigner,
    BadParties,
    NotHolder,
    NotLender,
    BadState,
    BadTerms,
    Locked,
    NotDue,
    InsufficientFunds,
    NotSponsor,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Agent {
    pub session_key: Address,
    pub sponsor: Address,
    pub frozen: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Lien {
    pub lender: u64,
    pub repay: u128,
    pub due: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Token {
    pub agent: u64,
    pub state: State,
    pub nonce: u64,
    pub content: B256,
    pub staked_until: u64,
    pub renter: Option<(u64, u64)>,
    pub lien: Option<Lien>,
}

pub fn address_of(vk: &VerifyingKey) -> Address {
    let pt = vk.to_encoded_point(false);
    Address::from_slice(&keccak256(&pt.as_bytes()[1..])[12..])
}

/// Signature 65 octets (r, s, v) d'une empreinte, comme le ferait l'enclave.
pub fn sign(key: &SigningKey, digest: B256) -> [u8; 65] {
    let (sig, rec) = key
        .sign_prehash_recoverable(digest.as_slice())
        .expect("signature");
    let mut out = [0u8; 65];
    out[..64].copy_from_slice(&sig.to_bytes());
    // v = 27 ou 28, comme l'attend ecrecover cote contrat.
    out[64] = 27 + rec.to_byte();
    out
}

fn recover(digest: B256, sig: &[u8; 65]) -> Option<Address> {
    let s = Signature::from_slice(&sig[..64]).ok()?;
    // Refuse les signatures malleables (s haut).
    if s.normalize_s().is_some() {
        return None;
    }
    let rec = RecoveryId::from_byte(sig[64].checked_sub(27)?)?;
    let vk = VerifyingKey::recover_from_prehash(digest.as_slice(), &s, rec).ok()?;
    Some(address_of(&vk))
}

pub struct Ledger {
    domain: Eip712Domain,
    agents: BTreeMap<u64, Agent>,
    tokens: BTreeMap<u64, Token>,
    vault: BTreeMap<u64, u128>,
    mint_nonces: BTreeMap<u64, u64>,
    next_token: u64,
}

impl Ledger {
    pub fn new(chain_id: u64, contract: Address) -> Self {
        Ledger {
            domain: eip712_domain! {
                name: "AgentOnlyNFT",
                version: "1",
                chain_id: chain_id,
                verifying_contract: contract,
            },
            agents: BTreeMap::new(),
            tokens: BTreeMap::new(),
            vault: BTreeMap::new(),
            mint_nonces: BTreeMap::new(),
            next_token: 1,
        }
    }

    pub fn digest(&self, intent: &Intent) -> B256 {
        intent.eip712_signing_hash(&self.domain)
    }

    pub fn token(&self, id: u64) -> Option<&Token> {
        self.tokens.get(&id)
    }

    pub fn agent(&self, id: u64) -> Option<&Agent> {
        self.agents.get(&id)
    }

    pub fn balance(&self, agent: u64) -> u128 {
        self.vault.get(&agent).copied().unwrap_or(0)
    }

    /// Compteur de mints d'un agent : empeche de rejouer une intention de mint.
    pub fn mint_nonce(&self, agent: u64) -> u64 {
        self.mint_nonces.get(&agent).copied().unwrap_or(0)
    }

    pub fn vault_total(&self) -> u128 {
        self.vault.values().sum()
    }

    pub fn tokens(&self) -> impl Iterator<Item = (&u64, &Token)> {
        self.tokens.iter()
    }

    // ---- Enrolement et role du sponsor -------------------------------------

    /// Inscrit la cle de session d'une instance attestee. Remplace la
    /// precedente. Aucun autre chemin n'inscrit de cle.
    pub fn enroll(
        &mut self,
        agent_id: u64,
        session_key: Address,
        sponsor: Address,
        attestation_valid: bool,
    ) -> Result<(), Error> {
        if !attestation_valid || agent_id == 0 {
            return Err(Error::BadAttestation);
        }
        match self.agents.get_mut(&agent_id) {
            Some(a) => {
                if a.sponsor != sponsor {
                    return Err(Error::NotSponsor);
                }
                a.session_key = session_key;
            }
            None => {
                self.agents.insert(
                    agent_id,
                    Agent { session_key, sponsor, frozen: false },
                );
            }
        }
        Ok(())
    }

    /// Depot ouvert a tous.
    pub fn deposit(&mut self, agent_id: u64, amount: u128) -> Result<(), Error> {
        if !self.agents.contains_key(&agent_id) {
            return Err(Error::UnknownAgent);
        }
        *self.vault.entry(agent_id).or_insert(0) += amount;
        Ok(())
    }

    /// Le sponsor peut retirer des USDC. Il ne peut jamais sortir un token :
    /// aucune fonction de ce type n'existe.
    pub fn withdraw(&mut self, caller: Address, agent_id: u64, amount: u128) -> Result<(), Error> {
        let a = self.agents.get(&agent_id).ok_or(Error::UnknownAgent)?;
        if a.sponsor != caller {
            return Err(Error::NotSponsor);
        }
        let bal = self.vault.entry(agent_id).or_insert(0);
        if *bal < amount {
            return Err(Error::InsufficientFunds);
        }
        *bal -= amount;
        Ok(())
    }

    pub fn set_frozen(&mut self, caller: Address, agent_id: u64, frozen: bool) -> Result<(), Error> {
        let a = self.agents.get_mut(&agent_id).ok_or(Error::UnknownAgent)?;
        if a.sponsor != caller {
            return Err(Error::NotSponsor);
        }
        a.frozen = frozen;
        Ok(())
    }

    fn pay(&mut self, from: u64, to: u64, amount: u128) -> Result<(), Error> {
        let bal = self.balance(from);
        if bal < amount {
            return Err(Error::InsufficientFunds);
        }
        self.vault.insert(from, bal - amount);
        *self.vault.entry(to).or_insert(0) += amount;
        Ok(())
    }

    // ---- Point d'entree unique ---------------------------------------------

    /// Execute une operation. `signed` contient une intention par partie.
    /// N'importe qui peut appeler : le relais ne peut rien modifier.
    pub fn execute(
        &mut self,
        token_id: u64,
        terms: Terms,
        signed: &[SignedIntent],
        now: u64,
    ) -> Result<u64, Error> {
        let op = terms.op();
        let terms_hash = terms.hash();

        // Etat courant du token, apres extinction d'une location echue.
        let current = if op == Op::Mint {
            if token_id != 0 {
                return Err(Error::BadToken);
            }
            None
        } else {
            let t = self.tokens.get_mut(&token_id).ok_or(Error::NoToken)?;
            if let (State::Rented, Some((_, expires))) = (t.state, t.renter) {
                if now >= expires {
                    t.state = State::Free;
                    t.renter = None;
                }
            }
            Some(*t)
        };
        let nonce = current.map(|t| t.nonce).unwrap_or(0);

        // Verification de chaque intention.
        let mut parties: Vec<u64> = Vec::with_capacity(signed.len());
        for s in signed {
            let i = &s.intent;
            if i.op != op as u8 {
                return Err(Error::BadOp);
            }
            if i.tokenId != U256::from(token_id) {
                return Err(Error::BadToken);
            }
            if i.termsHash != terms_hash {
                return Err(Error::TermsMismatch);
            }
            let agent_id = u64::try_from(i.agentId).map_err(|_| Error::UnknownAgent)?;
            // Un mint n'a pas encore de token : son compteur est celui de l'agent.
            let expected = if op == Op::Mint { self.mint_nonce(agent_id) } else { nonce };
            if i.tokenNonce != U256::from(expected) {
                return Err(Error::BadNonce);
            }
            if i.deadline < now {
                return Err(Error::Expired);
            }
            let agent = self.agents.get(&agent_id).ok_or(Error::UnknownAgent)?;
            if agent.frozen {
                return Err(Error::Frozen);
            }
            if recover(self.digest(i), &s.sig) != Some(agent.session_key) {
                return Err(Error::BadSigner);
            }
            parties.push(agent_id);
        }

        // Nombre de parties et designation croisee de la contrepartie.
        let two_party = matches!(op, Op::Transfer | Op::Swap | Op::Rent | Op::Pledge);
        if two_party {
            if parties.len() != 2 || parties[0] == parties[1] {
                return Err(Error::BadParties);
            }
            if signed[0].intent.counterparty != U256::from(parties[1])
                || signed[1].intent.counterparty != U256::from(parties[0])
            {
                return Err(Error::BadParties);
            }
        } else {
            if parties.len() != 1 || signed[0].intent.counterparty != U256::ZERO {
                return Err(Error::BadParties);
            }
        }
        let p0 = parties[0];

        // Mint : cree le token chez l'agent createur.
        if let Terms::Mint { content } = terms {
            let id = self.next_token;
            self.next_token += 1;
            *self.mint_nonces.entry(p0).or_insert(0) += 1;
            self.tokens.insert(
                id,
                Token {
                    agent: p0,
                    state: State::Free,
                    nonce: 1,
                    content,
                    staked_until: 0,
                    renter: None,
                    lien: None,
                },
            );
            return Ok(id);
        }

        let t = current.expect("token present hors mint");
        let need_free = matches!(
            op,
            Op::Transfer | Op::Swap | Op::Stake | Op::Rent | Op::Pledge | Op::Burn
        );
        if need_free && t.state != State::Free {
            return Err(Error::BadState);
        }
        // Claim est signe par le preteur ; tout le reste par le detenteur.
        if op != Op::Claim && p0 != t.agent {
            return Err(Error::NotHolder);
        }

        // Toutes les verifications faillibles passent avant la mutation.
        let mut next = t;
        match terms {
            Terms::Mint { .. } => unreachable!(),
            Terms::Transfer => {
                next.agent = parties[1];
            }
            Terms::Swap { price } => {
                self.pay(parties[1], p0, price)?;
                next.agent = parties[1];
            }
            Terms::Stake { until } => {
                if until <= now {
                    return Err(Error::BadTerms);
                }
                next.state = State::Staked;
                next.staked_until = until;
            }
            Terms::Unstake => {
                if t.state != State::Staked {
                    return Err(Error::BadState);
                }
                if now < t.staked_until {
                    return Err(Error::Locked);
                }
                next.state = State::Free;
                next.staked_until = 0;
            }
            Terms::Rent { price, expires } => {
                if expires <= now {
                    return Err(Error::BadTerms);
                }
                self.pay(parties[1], p0, price)?;
                next.state = State::Rented;
                next.renter = Some((parties[1], expires));
            }
            Terms::Pledge { principal, repay, due } => {
                if due <= now {
                    return Err(Error::BadTerms);
                }
                self.pay(parties[1], p0, principal)?;
                next.state = State::Pledged;
                next.lien = Some(Lien { lender: parties[1], repay, due });
            }
            Terms::Repay => {
                let lien = match (t.state, t.lien) {
                    (State::Pledged, Some(l)) => l,
                    _ => return Err(Error::BadState),
                };
                // Le remboursement reste possible apres l'echeance tant que le
                // preteur n'a pas saisi : sinon un preteur gele bloquerait le token.
                self.pay(p0, lien.lender, lien.repay)?;
                next.state = State::Free;
                next.lien = None;
            }
            Terms::Claim => {
                let lien = match (t.state, t.lien) {
                    (State::Pledged, Some(l)) => l,
                    _ => return Err(Error::BadState),
                };
                if p0 != lien.lender {
                    return Err(Error::NotLender);
                }
                if now <= lien.due {
                    return Err(Error::NotDue);
                }
                next.agent = lien.lender;
                next.state = State::Free;
                next.lien = None;
            }
            Terms::Burn => {
                self.tokens.remove(&token_id);
                return Ok(token_id);
            }
        }
        next.nonce = t.nonce + 1;
        self.tokens.insert(token_id, next);
        Ok(token_id)
    }
}
