//! Vecteurs de test croises : ce que le crate calcule et signe, a comparer au contrat.
//! Usage : cargo run --example vector -- <adresse du contrat>
use agent_only_core::*;
use alloy_primitives::{hex, Address, B256, U256};
use k256::ecdsa::SigningKey;

fn main() {
    let contract: Address = std::env::args().nth(1).expect("adresse du contrat").parse().expect("adresse");
    let l = Ledger::new(8453, contract);

    // 1. Empreinte d'une intention de gage.
    let pledge = Terms::Pledge { principal: 400, repay: 440, due: 1_900 };
    let intent = Intent {
        op: pledge.op() as u8,
        tokenId: U256::from(7),
        agentId: U256::from(1),
        counterparty: U256::from(2),
        termsHash: pledge.hash(),
        tokenNonce: U256::from(3),
        deadline: 1_000_000,
    };
    println!("PLEDGE_TERMS {}", pledge.hash());
    println!("PLEDGE_DIGEST {}", l.digest(&intent));

    // 2. Intention de mint signee par la cle [1; 32], comme le ferait l'enclave.
    let mint = Terms::Mint { content: B256::from([7; 32]) };
    let intent = Intent {
        op: mint.op() as u8,
        tokenId: U256::ZERO,
        agentId: U256::from(1),
        counterparty: U256::ZERO,
        termsHash: mint.hash(),
        tokenNonce: U256::ZERO,
        deadline: 1_000_000,
    };
    let key = SigningKey::from_slice(&[1; 32]).unwrap();
    println!("MINT_SIG 0x{}", hex::encode(sign(&key, l.digest(&intent))));
}
