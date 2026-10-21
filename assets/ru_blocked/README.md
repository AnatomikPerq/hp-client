Build input for the ru-blocked traffic profile: runetfreedom's "blocked in
Russia" domain and address lists (`domains.txt.gz`, `ips.txt.gz`) and
`manifest.json` with their ETags. `build_scripts/app/ru_blocked.py` fetches
them for every release build; a development build without them downloads the
lists when the profile is turned on.

The data comes from https://github.com/runetfreedom (antifilter community and
re:filter), see `LICENSE-THIRD-PARTY.md`.
