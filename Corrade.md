# Corrade

A [Corrade](https://grimore.org/corrade) is a metaverse bot / virtual-world grid
service (used for Second Life, OpenSim, and similar grids). This helper is
unrelated to Linux hardening — it lives in this repo because neohiro also
maintains Second Life tooling, and it is here for convenience only.

```bash
docker pull wizardrysteamworks/corrade:latest
```

```bash
docker run -d --name corrade --restart=unless-stopped -v /corrade/config:/etc/corrade -p 54379:54377 wizardrysteamworks/corrade:latest
```