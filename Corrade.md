```bash
docker pull wizardrysteamworks/corrade:latest
```
```bash
docker run -d --name corrade --restart=unless-stopped -v /corrade/config:/etc/corrade -p 54379:54377 wizardrysteamworks/corrade:latest
```


