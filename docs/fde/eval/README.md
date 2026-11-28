# Evaluation: does the assistant answer correctly from Kestrel's documents?

`questions.json` holds 10 questions written with the (fictional) team leads: each lists the facts a
correct answer must contain and the SOP it must cite; one question is deliberately not answerable and
must get "not found". `run_eval.py` asks the live API and scores it; the go-live bar is 90%.

Why it matters: "it looks good in the demo" is not evidence. A fixed question set turns answer
quality into a number you can track when the model, prompt, chunking or documents change, and every
wrong answer reported in the pilot becomes a new question here.

Note: the keyword grading is deliberately simple and strict (it can fail a correct answer phrased
differently); read the FAIL lines before changing anything.
