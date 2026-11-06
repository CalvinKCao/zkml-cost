*Disclosure: I wrote general outline of this short writeup and had Claude create the first draft. ~60% of the final text below is my own.*

# Does Artemis stay cheap as models grow?

Zero-knowledge ML lets a model provider return predictions along with a short proof of which model produced them. Building the proof is expensive, and it also has to tie to a public fingerprint of the model's weights (a commitment). Artemis is a recent method for making this tie cheap, and its paper reports at most 15 percent extra prover time. I wanted to see whether the cost stays small as models get bigger and the rest of the proof gets faster. I ran the authors' public code on one 16-thread CPU node, using the two bundled models with weights, an 8.1K-parameter MNIST network and a truncated MobileNet.

## Committing to a long vector

Committing to the weights means summing one elliptic-curve operation per weight, a step called a multi-scalar multiplication (MSM). The code then proves a fact about the committed data, which it calls opening. I timed commit plus open by itself on random vectors with two commitment schemes, KZG and IPA. The cost grows almost linearly with length. KZG took 0.27 s for 65 thousand entries and 207 s for 67 million, a log-log slope of 0.95. IPA took 1.4 s and 328 s for 65 thousand and 16 million entries, a slope of 0.98, and it spends most of its time in the opening. Verifying a KZG opening stays near 0.1 ms at every size.

![commit and open cost against vector length](results/plots/microbench_scaling.png)

## Inside full proofs

I split each Artemis-style run into three parts, the main proof, a linking opening which ties it to the committed weights, and the commit and open of the weights. On MNIST the last two took about 13 percent of the run. On the truncated MobileNet they took 33 s of 2981 s, about 1.1 percent. The same proof without commitments took 2880 s and 3041 s in two runs, so Artemis's cost disappears into the run-to-run noise. A sampling profiler puts 37 percent of MobileNet's CPU time in MSMs and 41 percent in fast Fourier transforms, with and without Artemis.

![share of prover time, normalised to the baseline](results/plots/e2e_breakdown.png)

I did not make the proof faster, so what follows is arithmetic on the measured shares. Suppose the commitment cost stays fixed while the rest of the proof speeds up. The rest of the MobileNet proof would need to get about 89 times faster before the commitment and its link take half of the prover time. If I count every MSM, including the main proof's own, MSMs already take 38 percent of the CPU samples and would reach half after the rest speeds up 1.7 times.

![commitment share as the base proof speeds up](results/plots/breakeven.png)

## Conclusion

In these two models, Artemis adds a small share of the prover time, and the share fell from about 13 percent on MNIST to about 1 percent on MobileNet. Commitment cost itself scales close to linearly over the sizes I measured. I only have two models, so I do not know whether the share keeps shrinking, and the profile numbers are rough.
