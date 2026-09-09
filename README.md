# TESTDIVOIP

A Bash tool I built to make VoIP route troubleshooting less repetitive.

When the PBX looks fine, the SIP trunk is up and the call still sounds bad, I usually want the same evidence again: packet loss, RTT, MTR, traceroute and some ASN context.

TESTDIVOIP puts those checks in one run and keeps a local report so I can compare what I saw instead of depending on terminal history.

— **Murilo Prestes**

## Why I built it

VoIP problems are not always inside Asterisk or FreePBX.

Sometimes the application is healthy and the network path is the part worth looking at. Running every command by hand works, but after doing it enough times I wanted the boring part to be repeatable.

That is basically this project.

## What it collects

For each configured office, remote site or SIP trunk target, the script tries to collect:

- ping RTT and packet loss
- MTR destination loss, average RTT and StDev
- numeric traceroute and hop count
- target ASN information through Team Cymru WHOIS
- a small troubleshooting score based on the measurements above

The MTR parser only accepts metrics from a line containing the requested target. If the destination is not present in the report, an intermediate hop is not treated as the endpoint.

The score is only a compact summary. Carrier names are not blacklisted and a numeric traceroute is not treated as proof that a route is international.

Also, MTR StDev is latency variation from the path test. It is useful context, but it is not the same thing as measuring RTP jitter from a live call.

## Requirements

I mainly use this on Debian and Ubuntu.

Commands used directly by the project include:

```text
bash
ping
mtr
traceroute
whois
timeout
bc
awk
sed
grep
find
```

The installer handles the main Debian/Ubuntu packages automatically. `timeout` and the other basic text/file utilities come from the normal base system on these distributions.

## Install

Clone the repository and run:

```bash
bash install.sh
```

Running it as root installs under `/opt/testdivoip` and creates `/usr/local/bin/testdivoip`.

As a normal user it installs under `~/.local/share/testdivoip` and creates `~/.local/bin/testdivoip`.

You can also run the project directly from the repository without installing it.

## Usage

Interactive mode:

```bash
./testdivoip.sh
```

Using a local config:

```bash
cp config/example.conf config/local.conf
./testdivoip.sh --config config/local.conf
```

Debug logging:

```bash
./testdivoip.sh --debug
```

List local reports:

```bash
./testdivoip.sh --list-reports
```

Print one report:

```bash
./testdivoip.sh --show-report Lab_20260909_120000.txt
```

## Configuration

`config/example.conf` uses documentation-only IP ranges. It is there to show the format, not to pretend there is a real customer behind the example.

For a real test I copy it to another `.conf` file and keep that file local. The `.gitignore` already excludes customer-specific config files.

The main script parses the fields it knows instead of sourcing the config as arbitrary shell code. Comments are expected on their own lines; a `#` inside a value is kept as part of that value.

Real customer names, IPs, office details and SIP trunk information should stay out of this repository.

## What a run looks like

```text
machine running TESTDIVOIP
        |
        +---- office / remote target
        |
        +---- SIP trunk target

        ping + MTR + traceroute + ASN context
                       |
                       v
              local report + audit log
```

For me the useful question is not “did the script say GOOD or BAD?”. It is:

```text
What did I actually measure?
        |
        v
Can I reproduce it?
        |
        v
Does the evidence point to the path, or do I need to keep looking?
```

## Output

Runtime data stays local:

```text
reports/
logs/
temp/
```

Those directories are ignored by Git. Runtime logs should not end up committed to the repository.

## Project structure

```text
.
├── .github/
│   └── workflows/
│       └── shell-checks.yml
├── config/
│   └── example.conf
├── functions/
│   ├── analysis.sh
│   ├── logging.sh
│   ├── network.sh
│   ├── presentation.sh
│   └── reporting.sh
├── tests/
│   └── test_testdivoip.sh
├── install.sh
├── testdivoip.sh
├── verify.sh
└── README.md
```

The main script handles the workflow. The files under `functions/` separate the parts that actually have different responsibilities without turning a small Bash tool into a framework.

## Verify and test the checkout

Repository structure, Bash syntax and runtime command checks:

```bash
bash verify.sh
```

Parser, configuration and CLI regression tests:

```bash
bash tests/test_testdivoip.sh
```

The pull-request workflow also runs ShellCheck and installs the project into a temporary directory before accepting the checks as green.

## About the score

I kept the score because it is handy for comparing runs, but I deliberately made it boring.

It is based on measured RTT, loss, latency variation and a small hop-count penalty. It does **not** automatically punish a route because a certain ASN or carrier appears in it.

It is not an SLA result, a carrier verdict or a production-readiness decision. I still read the actual measurements before deciding what is wrong.

## Status

This is a tool from my own troubleshooting and study work. I change it when I find something that makes the next investigation less manual or less misleading.

There are probably still things I will do differently later. That is fine. I would rather keep a small tool I can explain than call it a platform because the README looks impressive.

## License

MIT. See `LICENSE`.

**Murilo Prestes**
