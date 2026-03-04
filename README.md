# 🚀 RDGen - Proxmox & Cloudflare Enhanced Edition

Ce projet est un **Fork optimisé** du générateur RustDesk original. Il a été spécifiquement stabilisé pour les infrastructures auto-hébergées complexes.

### 🌟 Pourquoi utiliser ce Fork ?
Si vous faites tourner votre serveur sur une **VM Proxmox** (via Docker) et que vous utilisez des **Tunnels Cloudflare** ou un Reverse Proxy, la version originale peut échouer à cause des micro-coupures de l'API. Ce fork règle ces problèmes.

### ✨ Améliorations clés :
* **Build Resilient :** Ajout de `continue-on-error` sur les notifications de statut. Votre compilation ne crashera plus jamais à 5% ou 85% à cause d'une erreur réseau mineure.
* **Synchronisation API :** Correction du bug de communication via le secret `GENURL`.
* **Optimisation Windows :** Support complet des formats `.exe` et `.msi` avec accélération matérielle activée.
* **Multi-Plateforme :** Workflows testés et validés pour macOS (Intel/Silicon), Linux, Windows et Android.

### 🚀 Installation rapide
1. Forkez ce dépôt.
2. Configurez vos secrets GitHub (`SH_SECRET`, `ZIP_PASSWORD`, `GENURL`).
3. Lancez le build depuis votre instance rdgen locale.
