#!/usr/bin/env python3
"""Word Error Rate (WER) calculator for transcription accuracy testing."""
import sys

REFERENCE = [
    "The quick brown fox jumps over the lazy dog.",
    "Hello, my name is Kevin and I live in San Francisco.",
    "Can you please send me the quarterly report by Friday?",
    "The meeting starts at three thirty in conference room B.",
    "I think we should refactor the authentication module first.",
    "She ordered a large coffee with oat milk and no sugar.",
    "The temperature outside is seventy two degrees Fahrenheit.",
    "Please remind me to call the dentist tomorrow morning.",
    "We need to deploy the hotfix to production before midnight.",
    "The restaurant on Fifth Avenue has excellent pasta.",
    "I am going to the grocery store to buy eggs and bread.",
    "Machine learning models require large amounts of training data.",
    "Turn left at the next intersection and then go straight.",
    "The annual budget review is scheduled for next Wednesday.",
    "Python is a popular programming language for data science.",
    "Could you pick up the kids from school at four o'clock?",
    "The new feature reduces latency by approximately forty percent.",
    "It is raining outside so do not forget your umbrella.",
    "The board approved the merger with a unanimous vote.",
    "Open the terminal and run the build command.",
]

def normalize(text):
    """Lowercase, strip punctuation, collapse whitespace."""
    import re
    text = text.lower().strip()
    text = re.sub(r"[^\w\s]", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()

def wer(ref, hyp):
    """Compute word error rate using dynamic programming."""
    r = normalize(ref).split()
    h = normalize(hyp).split()
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1):
        d[i][0] = i
    for j in range(len(h) + 1):
        d[0][j] = j
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            if r[i-1] == h[j-1]:
                d[i][j] = d[i-1][j-1]
            else:
                d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + 1)
    return d[len(r)][len(h)], len(r)

def main():
    print("Transcription Accuracy Test")
    print("=" * 60)
    print(f"Enter transcription for each sentence (or 'skip' to skip):\n")

    total_errors = 0
    total_words = 0
    results = []

    for i, ref in enumerate(REFERENCE):
        print(f"[{i+1:2d}] REF: {ref}")
        hyp = input(f"     HYP: ").strip()
        if hyp.lower() == "skip":
            results.append((i+1, "SKIPPED", 0, 0))
            continue
        if hyp.lower() == "quit":
            break
        errors, words = wer(ref, hyp)
        rate = errors / words * 100 if words > 0 else 0
        total_errors += errors
        total_words += words
        status = "PERFECT" if errors == 0 else f"WER {rate:.0f}% ({errors}/{words})"
        results.append((i+1, status, errors, words))
        print(f"     --> {status}")
        print()

    print("\n" + "=" * 60)
    print("RESULTS SUMMARY")
    print("=" * 60)
    for num, status, _, _ in results:
        print(f"  Sentence {num:2d}: {status}")

    if total_words > 0:
        overall = total_errors / total_words * 100
        perfect = sum(1 for _, s, _, _ in results if s == "PERFECT")
        tested = sum(1 for _, s, _, _ in results if s != "SKIPPED")
        print(f"\nOverall WER: {overall:.1f}% ({total_errors} errors / {total_words} words)")
        print(f"Perfect sentences: {perfect}/{tested}")
    print()

if __name__ == "__main__":
    main()
