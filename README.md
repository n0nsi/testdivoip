# TESTDIVOIP

A Bash tool I built to make VoIP route troubleshooting less repetitive.

When a PABX looks fine, the SIP trunk is up and the call still sounds bad, I usually end up checking the same things again: latency, packet loss, jitter, traceroute, MTR and which networks the traffic is crossing.

This project puts those checks in one workflow and keeps the result in a report I can review later.

— **Murilo Prestes**

## Why I built it

VoIP problems are not always inside Asterisk or FreePBX.

Sometimes the application is healthy and the problem is the path between the server, the office and the carrier. Running every command by hand works, but after doing it enough times I wanted something repeatable.

That is where TESTDIVOIP came from.

It checks routes between a VoIP server and one or more destinations, such as offices or SIP carriers, and helps me compare what is happening in the network.

## What it checks

- ping and packet loss
- latency
- MTR
- traceroute
- hop count
- ASN information
- route changes
- basic VoIP quality scoring
- office and SIP trunk paths

The script also creates local reports and audit logs so I do not have to depend only on what was on the terminal at the time of the test.

## Requirements

I mainly use it on Debian-based systems.

Packages used by the project include:

```bash
mtr
dnsutils
whois
curl
jq
bc
net-tools
iproute2
```

Bash 4 or newer is recommended.

## Install

Clone the repository and run:

```bash
sudo bash install.sh
```

Or install the dependencies manually:

```bash
sudo apt update
sudo apt install -y mtr-tiny dnsutils whois curl jq bc net-tools iproute2
```

Then make the scripts executable if needed:

```bash
chmod +x testdivoip.sh
chmod +x functions/*.sh
```

## Usage

The simplest way is interactive mode:

```bash
./testdivoip.sh
```

Verbose output:

```bash
./testdivoip.sh --verbose
```

Debug mode:

```bash
./testdivoip.sh --debug
```

Using a configuration file:

```bash
./testdivoip.sh --config config/mycompany.conf
```

## Configuration

The repository has an example configuration in:

```text
config/example.conf
```

For a real environment, I copy the example and keep the real file local:

```bash
cp config/example.conf config/mycompany.conf
```

Customer names, real IP addresses, office information and SIP trunk details should not be committed to the repository.

## How I use it

A normal test for me looks roughly like this:

```text
VoIP server
   |
   +---- office / remote site
   |
   +---- SIP carrier
```

For each path I want evidence instead of guessing.

```text
Can I reach it?
      |
      v
What is the latency and loss?
      |
      v
Which path is the traffic taking?
      |
      v
Did the route change?
      |
      v
Is there something here that can hurt voice quality?
```

That is basically what the project automates.

## Output

Reports are written under:

```text
reports/
```

Audit logs are written under:

```text
logs/
```

These files are local operational data and should stay out of Git.

## Project structure

```text
testdivoip/
├── config/
├── functions/
├── install.sh
├── testdivoip.sh
├── verify.sh
└── README.md
```

The main script loads smaller modules from `functions/` for networking, analysis, logging and report generation.

## Important note about the score

The quality score is a troubleshooting aid, not a replacement for reading the actual network data.

A number by itself does not explain a VoIP problem. I still look at the MTR, packet loss, latency, route and the context of the environment before deciding what is wrong.

## Status

This is a project I use to study, test ideas and improve the way I troubleshoot VoIP networks.

There are parts I still want to improve. I would rather keep the project honest about that than call unfinished things "enterprise ready".

If I find a better way to test something in a real environment, it will probably end up here.

## License

MIT.

**Murilo Prestes**
