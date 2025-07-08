#!/usr/bin/env cargo

use anyhow::Result;
use aranya_crypto::default::DefaultEngine;
use aranya_crypto::keystore::fs_keystore::Store;
use aranya_keygen::KeyBundle;
use std::env;
use aranya_crypto::default::DefaultCipherSuite;

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: {} <device_name>", args[0]);
        eprintln!("Example: {} test_device_admin", args[0]);
        std::process::exit(1);
    }

    let device_name = &args[1];
    
    // Create a temporary directory for the keystore
    let keystore_dir = std::env::temp_dir().join(format!("aranya_keys_{}", device_name));
    std::fs::create_dir_all(&keystore_dir)?;
    
    // Initialize the crypto engine and keystore
    let (mut engine, _key) = DefaultEngine::from_entropy(aranya_crypto::Rng);
    let mut keystore = Store::open(&keystore_dir)?;
    
    // Generate the key bundle
    let key_bundle = KeyBundle::generate(&mut engine, &mut keystore)?;
    
    // Get the public keys
    let public_keys: aranya_keygen::PublicKeys<DefaultCipherSuite> = key_bundle.public_keys(&mut engine, &keystore)?;
    
    // Convert to hex strings using postcard serialization
    let identity_pk = hex::encode(postcard::to_allocvec(&public_keys.ident_pk)?);
    let signing_pk = hex::encode(postcard::to_allocvec(&public_keys.sign_pk)?);
    let encoding_pk = hex::encode(postcard::to_allocvec(&public_keys.enc_pk)?);
    let device_id = key_bundle.device_id.to_string();
    
    // Output the keys
    println!("Generated keys for {}:", device_name);
    println!("Device ID: {}", device_id);
    println!("Identity PK: {}", identity_pk);
    println!("Signing PK: {}", signing_pk);
    println!("Encoding PK: {}", encoding_pk);
    println!("");
    println!("Environment variables:");
    println!("export {}_DEVICE_ID=\"{}\"", device_name.to_uppercase(), device_id);
    println!("export {}_IDENTITY_PK=\"{}\"", device_name.to_uppercase(), identity_pk);
    println!("export {}_SIGNING_PK=\"{}\"", device_name.to_uppercase(), signing_pk);
    println!("export {}_ENCODING_PK=\"{}\"", device_name.to_uppercase(), encoding_pk);
    println!("");
    println!("Keystore location: {}", keystore_dir.display());
    println!("IMPORTANT: Copy the keystore directory to the daemon's keystore path to use this device's identity.");
    
    Ok(())
} 