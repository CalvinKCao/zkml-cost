*Disclosure: I wrote general outline of this short writeup and had Claude create the first draft. ~60% of the final text below is my own.*

# Does Artemis stay cheap as models grow?

Zero-knowledge ML lets someone doing inference return predictions with short proofs of which model produced it. Building the proof is expensive, and the proof also has to tie to a public fingerprint of the model's weights (a commitment). Artemis is a recent method for making this tie cheap, and its paper reports only up to 1.15x prover time. I wanted to see whether the cost stays small as models get bigger and the rest of the proof gets faster. I ran the authors' public code on one 16-thread CPU node, using the two bundled models with weights, an 8.1K-parameter MNIST network and a truncated Mobilenet.

## Committing to a long vector

Committing to the weights means summing one elliptic-curve operation per weight (MSM), and the code then proves a fact about the committed data, which it calls opening. I timed this step by itself on random vectors with two schemes, KZG and IPA. The cost grows almost linearly with length. KZG took 0.27 s for 65 thousand entries and 207 s for 67 million, with a log-log slope of 0.95. IPA took 1.4s and 328 s for 65 thousand and 16 million entries, with a slope of 0.98, and it spends most of its time in the opening. KZG verification stays near 0.1 ms at every size. Memory reaches 34 GiB at 67 million entries.

![commit and open cost against vector length](results/plots/microbench_scaling.png)

## Inside full proofs

I split each Artemis-style run into the main proof, a linking opening, which ties the proof to the committed weights, and the weight commit and open. On MNIST the last two took about 13 percent of the 5.4 s run. On the truncated MobileNet they took 33 s of 2981 s, about 1.1 percent. Without commitments the MobileNet proof took 2880 s and 3041 s in two runs, so the Artemis-style run falls inside the noise between them. A sampling profiler puts 37 percent of MobileNet's CPU time in MSMs and 41 percent in FFTs, with and without Artemis.

![share of prover time, normalised to the baseline](results/plots/e2e_breakdown.png)

To address the "much faster proof" part of the question, I did arithmetic on the measured shares and did not run anything faster. If the commitment time stays fixed, the rest of the MobileNet proof must get about 89 times faster before the commitment and its link reach half of the prover time. Counting every MSM, including the ones the main proof does for its own columns, MSMs already take 38 percent of the CPU samples and reach half after the rest speeds up by 1.7 times.

![commitment share as the base proof speeds up](results/plots/breakeven.png)


## Conclusion

In these two models, Artemis adds a small share of the prover time, and the share fell from about 13 percent on MNIST to about 1 percent on MobileNet. The commitment step itself scales close to linearly up to the sizes I measured, but this profile is rough.