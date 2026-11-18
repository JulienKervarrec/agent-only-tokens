//! aot-zkp exec|prove <quote.hex> <collateral-dir> <out-dir> [timestamp]
//!
//! Builds the input of Automata's DCAP v1.1 RISC Zero program for one TDX quote, from
//! collateral files read on chain by fetch_collateral.py, then either executes the program
//! (exec: no proof, gives the journal) or proves it with Groth16 (prove: journal and seal).
//! No network, no key.
use alloy_sol_types::{sol, SolType};
use anyhow::{bail, Context, Result};
use dcap_rs::types::collateral::Collateral;
use risc0_zkvm::{compute_image_id, default_executor, default_prover, ExecutorEnv, ProverOpts};
use std::{fs, path::Path};

/// Automata DCAP v1.1 guest, image id below (also checked at run time).
const ELF: &[u8] = include_bytes!("../guest/dcap-v1_1.elf");
const IMAGE_ID: &str = "cc80dc6c1c1f8bc524101b72b3900301dc87887457c8fcaf552e45e2a02b9695";
const SELECTOR: &str = "73c457ba";

type GuestInput = sol!((bytes, bytes, uint64));

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() < 5 {
        bail!("usage: aot-zkp exec|prove <quote.hex> <collateral-dir> <out-dir> [timestamp]");
    }
    let (mode, col, out) = (a[1].as_str(), Path::new(&a[3]), Path::new(&a[4]));

    let id = hex::encode(compute_image_id(ELF)?.as_bytes());
    println!("image id {id}");
    if id != IMAGE_ID {
        bail!("unexpected image id");
    }
    // The only RISC Zero route not paused on Base Sepolia is v3.0.0, selector 73c457ba.
    let params = risc0_zkvm::Groth16ReceiptVerifierParameters::default();
    let selector = hex::encode(&risc0_zkvm::sha::Digestible::digest(&params).as_bytes()[..4]);
    println!("groth16 selector {selector}");
    if selector != SELECTOR && mode == "prove" {
        bail!("this RISC Zero version does not match the verifier on Base Sepolia");
    }

    let quote = hex::decode(fs::read_to_string(&a[2])?.trim().trim_start_matches("0x"))?;
    let read = |f: &str| fs::read(col.join(f)).with_context(|| f.to_string());
    // TCB signing certificate then root, as Automata's pccs-reader writes the chain.
    let chain = pem::encode(&pem::Pem::new("CERTIFICATE", read("signing.der")?))
        + &pem::encode(&pem::Pem::new("CERTIFICATE", read("root.der")?));
    let collateral = Collateral::new(
        &read("root-crl.der")?,
        &read("platform-crl.der")?,
        chain.as_bytes(),
        &String::from_utf8(read("tcb-info.json")?)?,
        &String::from_utf8(read("qe-identity.json")?)?,
    )
    .context("collateral")?;
    let now = match a.get(5) {
        Some(t) => t.parse()?,
        None => std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs(),
    };
    let input =
        GuestInput::abi_encode_params(&(collateral.sol_abi_encode()?.as_slice(), quote.as_slice(), now));
    fs::create_dir_all(out)?;
    fs::write(out.join("input.hex"), hex::encode(&input))?;
    println!("input {} bytes, timestamp {now}", input.len());

    let env = ExecutorEnv::builder().write_slice(&input).build()?;
    let started = std::time::Instant::now();
    if mode == "exec" {
        let session = default_executor().execute(env, ELF)?;
        println!("cycles {}", session.cycles());
        fs::write(out.join("journal.hex"), hex::encode(&session.journal.bytes))?;
    } else if mode == "prove" {
        let receipt = default_prover().prove_with_opts(env, ELF, &ProverOpts::groth16())?.receipt;
        receipt.verify(compute_image_id(ELF)?)?;
        let g = receipt.inner.groth16()?;
        // Seal as the RISC Zero router expects it: verifier selector, then the Groth16 proof.
        let mut seal = hex::decode(SELECTOR)?;
        if g.verifier_parameters.as_bytes()[..4] != seal[..] {
            bail!("proof made for another verifier");
        }
        seal.extend_from_slice(&g.seal);
        fs::write(out.join("journal.hex"), hex::encode(&receipt.journal.bytes))?;
        fs::write(out.join("seal.hex"), hex::encode(&seal))?;
    } else {
        bail!("mode must be exec or prove");
    }
    println!("{mode} done in {:?}", started.elapsed());
    Ok(())
}
