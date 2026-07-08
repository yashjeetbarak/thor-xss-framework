# Thor v1.0.0 Release Notes

Thor v1.0.0 is the first public open-source release of **The Automated Recon & XSS Hunting Framework**.

## Highlights

- Bash 5+ workflow designed for Kali Linux.
- Plugin-based recon pipeline.
- Dalfox-only XSS scanning with strict scoped input validation.
- Safer default Dalfox batching to avoid open-file exhaustion.
- TXT, JSON, and modern HTML reports with consistent finding counts.
- CLI and Zenity/YAD GUI usage.
- GitHub-ready documentation, templates, security policy, and CI workflows.

## Upgrade notes

Use this release as a clean install. Do not merge it into older Thor folders that contained legacy scanner integrations or temporary scan artifacts.

```bash
cd ~
mv Thor Thor_old_$(date +%F_%H-%M-%S) 2>/dev/null
unzip Thor-github-ready-v1.0.0.zip -d Thor
cd Thor
chmod +x install.sh thor.sh gui/thor-gui.sh
./install.sh
```

## Safety

Thor is intended only for assets you own or are explicitly authorized to assess. It does not include exploit chaining, bypass logic, or unauthorized access functionality.
