# 🏠 Homelab Infrastructure

This repository contains the GitOps-managed configuration for my home Kubernetes cluster using FluxCD, K3s, and various self-hosted services.

## 🚀 Overview

This repository follows a GitOps approach to manage and automate the infrastructure and services running in my homelab. All Kubernetes manifests and Helm releases are stored and version-controlled here, making it easy to replicate, recover, and scale the setup.

Originally, I ran everything with Docker and Docker Compose. But as my setup grew in complexity, I decided to migrate to Kubernetes.

Admittedly, this is overkill for a homelab — but that's kind of the point. This project is my playground for learning Kubernetes through hands-on experience, while also powering the self-hosted services I use every day.

## ⚙️ Infrastructure Specs

- **CPU:** Intel Core i7-8700  
- **Memory:** 16 GB DDR4 RAM  
- **Storage:** 12 TB HDD  
- **Hypervisor:** Proxmox VE  
- **Kubernetes Distribution:** [K3s](https://k3s.io/)  
- **OS:** Ubuntu Server (running in VM)

## 📦 Core Tools & Technologies

- [Proxmox VE](https://www.proxmox.com/) – Virtualization hyprvisor platform
- [FluxCD](https://fluxcd.io/) – GitOps operator for continuous delivery
- [K3s](https://k3s.io/) – Lightweight Kubernetes distribution
- [Renovate](https://www.mend.io/free-developer-tools/renovate/) – Dependency update automation  

## 🛠️ Features & Services

- 📺 Jellyfin, Sonarr, Radarr, and other media services  
- 🔐 Qbittorrent with Gluetun for VPN routing and safely downloading torrents  
- 📈 Grafana & Prometheus monitoring and observability stack  
- 🔄 Automated updates with Renovate and Flux

## 📌 Goals

- Automate and version all infrastructure and services  
- Ensure reproducibility and recoverability  
- Improve DevOps skills using real-world tools and patterns  
- Provide secure, performant, and resilient home services 