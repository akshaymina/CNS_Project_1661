# ChatAFL — LLM Guided Protocol Fuzzing

Reproduction project for the NDSS 2024 research paper **"Large Language Model guided Protocol Fuzzing"**.  
Original repository: https://github.com/ChatAFLndss/ChatAFL

---

## What This Is

**Fuzzing** is an automated security testing technique that sends large numbers of random inputs to a program and watches for crashes. Each crash is a potential vulnerability.

**Protocol fuzzing** applies this to networked servers (FTP, HTTP, email servers, etc.). The challenge is that these servers are *stateful* — they only accept messages in a specific order. A fuzzer must send valid message sequences, not random bytes.

**ChatAFL** improves on the existing state-of-the-art tool (AFLNet) by using a Large Language Model to:

1. **Extract the protocol grammar** — so mutations stay structurally valid instead of being immediately rejected
2. **Enrich the seed corpus** — ask the LLM what message types are missing and add them
3. **Break coverage stalls** — when the fuzzer gets stuck, ask the LLM for a message that leads to a new server state

---

## Protocols and Servers Tested

| Server | Protocol | Description |
|--------|----------|-------------|
| pure-ftpd | FTP | File Transfer Protocol |
| proftpd | FTP | Alternative FTP server |
| live555 | RTSP | Real-time streaming |
| kamailio | SIP | VoIP / internet calling |
| exim | SMTP | Email transfer |
| lighttpd | HTTP | Web server |

---

## Fuzzer Variants

| Variant | Strategies Enabled |
|---------|--------------------|
| AFLNet | None (baseline) |
| ChatAFL-CL1 | Grammar extraction only |
| ChatAFL-CL2 | Grammar + seed enrichment |
| ChatAFL | All three (full system) |

Expected result: AFLNet < CL1 < CL2 < ChatAFL in coverage.

---

## Requirements

- Ubuntu 20.04 or 22.04
- Docker
- Python 3 with matplotlib and pandas
- A free Groq API key — sign up at https://console.groq.com (no credit card needed)
- At least 30 GB free disk space and 8 GB RAM

---

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/ChatAFLndss/ChatAFL.git
cd ChatAFL
```

### 2. Install dependencies

```bash
chmod +x deps.sh
./deps.sh
```

If Docker is not installed automatically:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
```

### 3. Apply the code changes

See the **Code Changes** section below, then copy the fixed files:

```bash
cp chat-llm.c ChatAFL/chat-llm.c
cp chat-llm.h ChatAFL/chat-llm.h

cp chat-llm.c ChatAFL-CL1/chat-llm.c
cp chat-llm.h ChatAFL-CL1/chat-llm.h

cp chat-llm.c ChatAFL-CL2/chat-llm.c
cp chat-llm.h ChatAFL-CL2/chat-llm.h
```

### 4. Set your Groq API key

```bash
export GROQ_API_KEY="gsk_your_key_here"
```

### 5. Build Docker images

```bash
chmod +x setup.sh
KEY=$GROQ_API_KEY ./setup.sh
```

This takes approximately 40 minutes. Docker caches completed steps, so if it fails partway through just re-run the same command.

### 6. Verify images were built

```bash
docker images | grep -E "chatafl|aflnet"
```

You should see one image per fuzzer per target server.

---

## Running Experiments

### Quick test (5 minutes)

```bash
./run.sh 1 5 pure-ftpd chatafl
```

### Main comparison experiment (4 hours)

```bash
./run.sh 5 240 kamailio,pure-ftpd,live555 chatafl,aflnet
```

### Ablation study (4 hours)

```bash
./run.sh 5 240 proftpd,exim chatafl,chatafl-cl1,chatafl-cl2
```

Arguments: `./run.sh <repetitions> <minutes> <targets> <fuzzers>`

Monitor running containers:

```bash
watch docker ps
docker logs -f <container_id>
```

---

## Analyzing Results

```bash
chmod +x analyze.sh
./analyze.sh kamailio,pure-ftpd,live555 240
./analyze.sh proftpd,exim 240
```

Output graphs are saved in `res_<target>_<timestamp>/` folders as PNG files:

- `cov_over_time_<target>.png` — branch coverage over time
- `state_over_time_<target>.png` — protocol states discovered over time

---

## Code Changes

The original implementation uses OpenAI's paid API. This project replaces it with the **Groq free API** using the `llama-3.3-70b-versatile` model. Three bugs were also fixed in the process.

### chat-llm.h

**Change 1 — Remove hardcoded fake API token**

```c
// BEFORE (causes HTTP 401 on every API call):
#define OPENAI_TOKEN "1"

// AFTER:
/* API key is read at runtime via getenv("GROQ_API_KEY") in chat-llm.c */
```

### chat-llm.c

**Change 2 — Read API key from environment at runtime**

```c
// BEFORE:
char *auth_header = "Authorization: Bearer " OPENAI_TOKEN;

// AFTER:
const char *groq_api_key = getenv("GROQ_API_KEY");
if (groq_api_key == NULL || strlen(groq_api_key) == 0) {
    printf("[ChatAFL] ERROR: GROQ_API_KEY environment variable is not set!\n");
    return NULL;
}
char *auth_header = NULL;
asprintf(&auth_header, "Authorization: Bearer %s", groq_api_key);
```

**Change 3 — Fix swapped arguments and hardcode the Groq model**

```c
// BEFORE (prompt in model slot, int MAX_TOKENS passed as %s = crash):
asprintf(&data,
    "{\"model\": \"%s\", \"messages\": [{\"role\": \"user\", \"content\": \"%s\"}], \"max_tokens\": %d, \"temperature\": 0}",
    prompt, MAX_TOKENS, temperature);

// AFTER:
asprintf(&data,
    "{\"model\": \"llama-3.3-70b-versatile\", \"messages\": [{\"role\": \"user\", \"content\": \"%s\"}], \"max_tokens\": %d, \"temperature\": %f}",
    prompt, MAX_TOKENS, temperature);
```

**Change 4 — Fix response parsing to match Groq's format**

```c
// BEFORE (reads choices[0].text — old OpenAI completions format, doesn't exist in Groq):
json_object *jobj4 = json_object_object_get(first_choice, "text");
data = json_object_get_string(jobj4);

// AFTER (reads choices[0].message.content — correct for chat completions):
json_object *jobj4 = json_object_object_get(first_choice, "message");
json_object *jobj5 = json_object_object_get(jobj4, "content");
data = json_object_get_string(jobj5);
```

**Change 5 — Free the dynamically allocated auth header**

```c
// Add this before the existing free(data):
if (auth_header != NULL) {
    free(auth_header);
}
```

All changes must be applied to `chat-llm.c` and `chat-llm.h` in all three folders: `ChatAFL/`, `ChatAFL-CL1/`, and `ChatAFL-CL2/`. The files are identical across all three — the same fixed copy works for all.

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `permission denied` on docker | User not in docker group | `sudo usermod -aG docker $USER` then log out and back in |
| HTTP 401 from API | Wrong or missing Groq key | Check `echo $GROQ_API_KEY` is set correctly |
| Container exits immediately | API failure inside Docker | Run `docker logs <id>` to see the actual error |
| `setup.sh` fails halfway | Network issue during build | Re-run `KEY=$GROQ_API_KEY ./setup.sh` — Docker resumes from cache |
| No plots after analyze.sh | Results not ready | Make sure `run.sh` fully completed first |

---

## Cleanup

```bash
chmod +x clean.sh
./clean.sh
```

Removes all containers and frees disk space.

---

## References

- Meng R., Mirchev M., Bohme M., Roychoudhury A. *"Large Language Model guided Protocol Fuzzing."* NDSS 2024.
- Pham V.T., Bohme M., Roychoudhury A. *"AFLNet: A Greybox Fuzzer for Network Protocols."* ICST 2020.
- Natella R., Bohme M. *"ProFuzzBench: A Benchmark for Stateful Protocol Fuzzing."* ISSTA 2021.

