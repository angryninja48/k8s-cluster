# SOPS Encryption

### Create an encrypted file using SOPS

Note: This assumes GPG keys are setup

Edit .sops.yaml and add new path_regex

```
- path_regex: terraform/secrets.yaml
  pgp: >-
    E079749E7AE92868BCFD1885801E691531E60E05,
    38B3D9E3FC45985638BCE8D45414DE6521F422DD
```

Encrypt the file

```
sops --encrypt --in-place terraform/secret.sops.yaml
```
