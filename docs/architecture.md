# Architecture Technique

## Vue d'ensemble

L'architecture est organisée en couches de sécurité superposées (Defense in Depth).

## Composants Principaux

### IAM Stack
- Keycloak : Identity Provider (OIDC/SAML)
- RBAC : Contrôle d'accès Kubernetes

### Detection Stack
- Falco : Runtime security (eBPF)
- Wazuh : HIDS + vulnerability scanner

### Observability Stack
- ELK Stack : Logs
- Prometheus + Grafana : Metrics

[Documentation détaillée à venir]
