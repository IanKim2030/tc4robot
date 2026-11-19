# tc4robot

A Robot Framework-based regression automation testing tool for SK Telecom's **PG (PCRF Gateway)**.
Six test groups: NAG (including PCF integration), LRS, UPM, CDS, NWDAF, and RTS.

## Agent Instructions

Read [AGENTS.md](AGENTS.md) before making changes. It links to task-specific
references and the [development workflow](docs/agent/workflow.md).

## Installation

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

PDB checks require `pyodbc` and the appropriate system ODBC driver.
CDS connects to PDB in suite setup, so missing DB dependencies or configuration
can prevent the entire suite from running. See [environment configuration](docs/ENVIRONMENTS.md).
Additional service dependencies are described in `requirements.txt`.

## Execution

```bash
bash run_tests.sh nag         # A node suite: nag/pcf/lrs/upm/cds/nwdaf/rts
bash run_tests.sh all         # All suites
bash run_tests.sh smoke       # Tests tagged smoke
bash run_tests.sh nag stg     # Environment: dev by default, stg, or supplied prd
```

These are live integration commands; the runner seeds configuration data by default.
See the [workflow](docs/agent/workflow.md) before running them.
Reports: `results/<YYYYMMDD_HHMMSS>/report.html` and `log.html`.

## Documentation

See [the applied structure and validation summary](docs/agent/current-state.md) for the current refactoring status.

[docs/README.md](docs/README.md) is the complete documentation index.
Read the relevant node specification before writing TCs.

| Document | Purpose |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Four-layer structure and module layout |
| [Interfaces](docs/INTERFACES.md) | Node interface matrix and opcode collisions |
| [TC conventions](tests/TC_CONVENTION.md) | Naming, tags, templates, and validation |
| [Resources](resources/AGENTS.md) | Shared keywords, variables, and Python helpers |
| [Environments](docs/ENVIRONMENTS.md) | dev/stg/prd configuration |
| [Node specifications](tests/AGENTS.md) | Specifications for all six test groups |
| [Call flows](docs/callflow/) | Developer-only reference for understanding internal processing |

## Interface Specification Inventory

Specification titles below are translated descriptions; retain original source documents
as the authority for their exact titles and contents. Status labels reflect the existing inventory.

| No. | Process | Connection | Specification | Status | Notes |
|---|---|---|---|---|---|
| 01 | PG.BNOTI | NAG (C) → PG.BNOTI (S) | PG–NAG HFC/ADOT Service Interface, 2023-07-18 | Complete | ... |
| 02 | PG.BNOTI | PCF (C) → PG.BONTI (S) | PCRF–PG ZONE Notification Processing Interface, 2021-03-29 | Complete | ... |
| 03 | PG.BNOTI | BNOTI (C) → PG.LRS (S) | PG–LRS Information Query Interface, 2021021, V1.7 | Complete | ... |
| 04 | PG.LRS | LRS (C) → PG.LRS (S) | PG–LRS Information Query Interface, 2021021, V1.7 | Complete | ... |
| 05 | PG.LRS | PG.LRS (C) → PCF (S) | PCRF/PCF–PG RAR Optimization Interface, v0.8, 2023-11-15 | Complete | ... |
| 06 | PG.UPM | ... | UPM–PG.BSUBS HFC Service Interface, v1.1 | In progress | ... |
| 90 | PG.SCMQOS | ITM → PG.SCMQOS | ... | Implementation required | Base-station congestion control |
| 91 | PG.NWMQOS | NWDAF → PG.NWMQOS | PG Interface, V1.2, 2024-09-20 | Implementation required | Base-station congestion control |

### Inventory Tips

- Transport examples: REST API (HTTPS), gRPC, sockets, SFTP, DB Link.
- Data format examples: JSON, XML, fixed-width messages, CSV.
- Status examples: pending, design, development, testing, complete, on hold.

## Components and Acronyms

| Acronym | Full name | Role or description |
|---|---|---|
| PG | PCRF Gateway | ... |
| NAG | Network Access Gateway | ... |
| MSS | Mobile Switching Server/System | Call routing and subscriber location management |
| ABC | A-side, B-side / Call Processing | ... |
| HD Voice | High Definition Voice | ... |
| HFC | Home-Fi Call | ... |
| LRS | Location Retrieval System | ... |
| NWDAF | Network Data Analytics Function | ... |
| CDS | Customer Data Distributed | ... |
| RDS | Reserved Data Distributed | ... |
| ITM | Integrated Traffic Manager/Management | Applies traffic policies and manages subscriber service quality and policy information using telecommunications subscriber databases |
| PG.BNOTI | BaroD Noti | ... |

## NAG and PCF Integration

`tests/nag/nag_tests.robot` contains all 17 cases in one suite: NAG requests
001–007 and PCF integration 008–017. `bash run_tests.sh nag` runs all cases;
`bash run_tests.sh pcf` selects the PCF-tagged subset while retaining other user
filters. The NAG guide documents lazy initialization, the one-way path transition,
and PCF registration prerequisites. Protocol-specific resources keep their names.
