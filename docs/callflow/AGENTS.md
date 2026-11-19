# Developer Call-Flow Instructions

These documents explain internal PG processing for developers. They are not
required reading for TC authoring and do not own TC requirements or common policy.

- Preserve participant IDs, message directions, protocol constants, and the distinction between evidence and assumptions.
- Put TC prerequisites, ordering constraints, and acceptance criteria in the relevant node specification, linking from here as needed.
- `cds_callflow.md` is generated: edit `gen_callflow.py`, then run `python docs/callflow/gen_callflow.py` from the repository root.
- The generator imports `libraries/CdsHelper.py`; keep generated output in English and check reproducibility.
- Validate Mermaid structure and incoming section links after editing diagrams or headings.
