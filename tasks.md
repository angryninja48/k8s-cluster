# TODO
1. Fix ceph
- Replicated pool size
- Mon & Mgr
- Config override

2. Thanos Objectoreconfig
- Change the configmap to point to the thanos storage bucket

3. Nginx cert
- Change default cert in kubernetes/apps/networking/ingress-nginx/app/helmrelease.yaml:67 to production
- Uncomment out production certficates in kubernetes/apps/networking/ingress-nginx/certificates/certificates.yaml
- Uncomment out production issuer in kubernetes/apps/cert-manager/cert-manager/issuers/issuers.yaml
