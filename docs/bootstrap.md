# Preparing nodes

### Run ansible playbook

```
cd git/k3s-gitops/ansible
ansible-playbook playbooks/ubuntu/prepare.yml --ask-become
```

### Nuking

```
ansible-playbook playbooks/ubuntu/prepare.yml --ask-become -l k3s-4
```

### Resize VG
```
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```
