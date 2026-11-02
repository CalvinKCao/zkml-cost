
use std::fs::File;
use std::io::{BufReader, Write};
use std::path::Path;
use std::time::Instant;

use ff::Field;
use group::Curve;
use halo2_proofs::{
    poly::{
        commitment::{Blind, Params, ParamsProver, Prover, Verifier},
        ipa::{
            commitment::ParamsIPA,
            msm::MSMIPA,
            multiopen::{ProverIPA, VerifierIPA},
        },
        kzg::{
            commitment::ParamsKZG,
            msm::DualMSM,
            multiopen::{ProverSHPLONK, VerifierSHPLONK},
        },
        Coeff, Polynomial, ProverQuery, VerifierQuery,
    },
    transcript::{Blake2bRead, Blake2bWrite, Challenge255, TranscriptReadBuffer, TranscriptWriterBuffer},
};
use halo2curves::bn256::Bn256;
use halo2curves::pairing::Engine;
use halo2curves::pasta::EqAffine;
use rand::thread_rng;
use rand_core::OsRng;

fn vm_hwm_kib() -> u64 {
    let status = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    for line in status.lines() {
        if let Some(rest) = line.strip_prefix("VmHWM:") {
            return rest.split_whitespace().next().unwrap_or("0").parse().unwrap_or(0);
        }
    }
    0
}

fn csv_header() {
    println!(
        "scheme,pass,k,n,params_source,setup_or_load_s,poly_gen_s,commit_s,open_s,verify_s,commit_plus_open_s,peak_rss_kib,proof_bytes"
    );
}

fn load_or_setup_kzg(k: u32, params_path: Option<&str>) -> (ParamsKZG<Bn256>, String, f64) {
    if let Some(path) = params_path {
        if Path::new(path).is_file() {
            let t = Instant::now();
            let mut reader = BufReader::new(File::open(path).expect("open params"));
            let params = ParamsKZG::<Bn256>::read(&mut reader).expect("read kzg params");
            return (params, "load".to_string(), t.elapsed().as_secs_f64());
        }
    }
    let t = Instant::now();
    let params = ParamsKZG::<Bn256>::setup(k, OsRng);
    (params, "setup".to_string(), t.elapsed().as_secs_f64())
}

fn load_or_setup_ipa(k: u32, params_path: Option<&str>) -> (ParamsIPA<EqAffine>, String, f64) {
    if let Some(path) = params_path {
        if Path::new(path).is_file() {
            let t = Instant::now();
            let mut reader = BufReader::new(File::open(path).expect("open params"));
            let params: ParamsIPA<EqAffine> =
                Params::read(&mut reader).expect("read ipa params");
            return (params, "load".to_string(), t.elapsed().as_secs_f64());
        }
    }
    let t = Instant::now();
    let params = ParamsIPA::<EqAffine>::new(k);
    (params, "setup".to_string(), t.elapsed().as_secs_f64())
}

fn cache_params(params_path: Option<&str>, write_fn: impl FnOnce(&mut File) -> std::io::Result<()>) {
    let Some(path) = params_path else { return };
    if Path::new(path).is_file() {
        return;
    }
    if let Some(parent) = Path::new(path).parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    match File::create(path) {
        Ok(mut f) => match write_fn(&mut f) {
            Ok(()) => eprintln!("cached params {path}"),
            Err(e) => eprintln!("warn: failed to cache params: {e}"),
        },
        Err(e) => eprintln!("warn: failed to create params file: {e}"),
    }
}

fn bench_kzg(k: u32, passes: usize, params_path: Option<&str>) {
    let n = 1usize << k;
    eprintln!("kzg Bn256 k={k} n={n} passes={passes}");
    let (params, source, setup_s) = load_or_setup_kzg(k, params_path);
    eprintln!("params {source} {setup_s:.3}s hwm_kib={}", vm_hwm_kib());

    let t = Instant::now();
    let mut rng = thread_rng();
    let coeffs: Vec<<Bn256 as Engine>::Scalar> =
        (0..n).map(|_| <Bn256 as Engine>::Scalar::random(&mut rng)).collect();
    let poly = Polynomial::<<Bn256 as Engine>::Scalar, Coeff>::from_coefficients_vec(coeffs);
    let poly_gen_s = t.elapsed().as_secs_f64();
    let beta = <Bn256 as Engine>::Scalar::random(&mut rng);
    let rho = poly.evaluate(beta);
    let blind = Blind::default();

    for pass in 1..=passes {
        let t = Instant::now();
        let poly_com = std::hint::black_box(params.commit(&poly, blind).to_affine());
        let commit_s = t.elapsed().as_secs_f64();

        let t = Instant::now();
        let mut transcript = Blake2bWrite::<_, _, Challenge255<_>>::init(vec![]);
        let queries = vec![ProverQuery {
            point: beta,
            poly: &poly,
            blind,
        }];
        ProverSHPLONK::new(&params)
            .create_proof(&mut OsRng, &mut transcript, queries)
            .expect("kzg open");
        let proof = transcript.finalize();
        let open_s = t.elapsed().as_secs_f64();

        let t = Instant::now();
        let verifier = VerifierSHPLONK::new(&params.verifier_params());
        let mut vtranscript = Blake2bRead::<_, _, Challenge255<_>>::init(proof.as_slice());
        let vqueries = std::iter::empty()
            .chain(Some(VerifierQuery::new_commitment(&poly_com, beta, rho)));
        let msm = DualMSM::new(&params);
        assert!(
            verifier.verify_proof(&mut vtranscript, vqueries, msm).is_ok(),
            "kzg verify failed"
        );
        let verify_s = t.elapsed().as_secs_f64();
        let hwm = vm_hwm_kib();
        println!(
            "kzg,{pass},{k},{n},{source},{setup_s:.6},{poly_gen_s:.6},{commit_s:.6},{open_s:.6},{verify_s:.6},{:.6},{hwm},{}",
            commit_s + open_s,
            proof.len()
        );
        let _ = std::io::stdout().flush();
        eprintln!(
            "pass {pass}: commit {commit_s:.3}s open {open_s:.3}s verify {verify_s:.3}s hwm_kib {hwm}"
        );
    }

    cache_params(params_path, |f| params.write(f));
}

fn bench_ipa(k: u32, passes: usize, params_path: Option<&str>) {
    let n = 1usize << k;
    eprintln!("ipa pasta-Eq k={k} n={n} passes={passes}");
    let (params, source, setup_s) = load_or_setup_ipa(k, params_path);
    eprintln!("params {source} {setup_s:.3}s hwm_kib={}", vm_hwm_kib());

    let t = Instant::now();
    let mut rng = thread_rng();
    let coeffs: Vec<<EqAffine as group::prime::PrimeCurveAffine>::Scalar> = (0..n)
        .map(|_| <EqAffine as group::prime::PrimeCurveAffine>::Scalar::random(&mut rng))
        .collect();
    type Scalar = <EqAffine as group::prime::PrimeCurveAffine>::Scalar;
    let poly = Polynomial::<Scalar, Coeff>::from_coefficients_vec(coeffs);
    let poly_gen_s = t.elapsed().as_secs_f64();
    let beta = Scalar::random(&mut rng);
    let rho = poly.evaluate(beta);
    let blind = Blind::default();

    for pass in 1..=passes {
        let t = Instant::now();
        let poly_com = std::hint::black_box(params.commit(&poly, blind).to_affine());
        let commit_s = t.elapsed().as_secs_f64();

        let t = Instant::now();
        let mut transcript = Blake2bWrite::<_, EqAffine, Challenge255<_>>::init(vec![]);
        let queries = vec![ProverQuery {
            point: beta,
            poly: &poly,
            blind,
        }];
        ProverIPA::new(&params)
            .create_proof(&mut OsRng, &mut transcript, queries)
            .expect("ipa open");
        let proof = transcript.finalize();
        let open_s = t.elapsed().as_secs_f64();

        let t = Instant::now();
        let verifier = VerifierIPA::new(&params.verifier_params());
        let mut vtranscript = Blake2bRead::<_, EqAffine, Challenge255<_>>::init(proof.as_slice());
        let vqueries = std::iter::empty()
            .chain(Some(VerifierQuery::new_commitment(&poly_com, beta, rho)));
        let msm = MSMIPA::new(&params);
        assert!(
            verifier.verify_proof(&mut vtranscript, vqueries, msm).is_ok(),
            "ipa verify failed"
        );
        let verify_s = t.elapsed().as_secs_f64();
        let hwm = vm_hwm_kib();
        println!(
            "ipa,{pass},{k},{n},{source},{setup_s:.6},{poly_gen_s:.6},{commit_s:.6},{open_s:.6},{verify_s:.6},{:.6},{hwm},{}",
            commit_s + open_s,
            proof.len()
        );
        let _ = std::io::stdout().flush();
        eprintln!(
            "pass {pass}: commit {commit_s:.3}s open {open_s:.3}s verify {verify_s:.3}s hwm_kib {hwm}"
        );
    }

    cache_params(params_path, |f| Params::write(&params, f));
}

fn main() {
    let mut args = std::env::args().skip(1);
    let scheme = args.next().expect("scheme: kzg or ipa");
    let k: u32 = args.next().expect("k").parse().expect("k integer");
    let passes: usize = args
        .next()
        .unwrap_or_else(|| "2".to_string())
        .parse()
        .expect("passes");
    let params_path = args.next();
    if k > 26 {
        eprintln!("refusing k={k}; cap is 26 so a single run cannot exhaust the node");
        std::process::exit(2);
    }
    eprintln!(
        "rayon threads {} hwm_kib_start {}",
        rayon::current_num_threads(),
        vm_hwm_kib()
    );
    csv_header();
    match scheme.as_str() {
        "kzg" => bench_kzg(k, passes, params_path.as_deref()),
        "ipa" => bench_ipa(k, passes, params_path.as_deref()),
        other => {
            eprintln!("unknown scheme {other}");
            std::process::exit(2);
        }
    }
}
