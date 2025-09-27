# 🏠 Homelab Infrastructure

This repository contains the GitOps-managed configuration for my home Kubernetes cluster using FluxCD, K3s, and various self-hosted services.

## Overview

This repository follows a GitOps approach to manage and automate the infrastructure and services running in my homelab. All Kubernetes manifests and Helm releases are stored and version-controlled here, making it easy to replicate, recover, and scale the setup.

Originally, I ran everything with Docker and Docker Compose. But as my setup grew in complexity, I decided to migrate to Kubernetes.

Admittedly, this is overkill for a homelab - but that's kind of the point. This project is my playground for learning Kubernetes through hands-on experience, while also powering the self-hosted services I use every day.

## Infrastructure Specs

### Control Plane 
**Dell Vostro Laptop** 
- **CPU:** Intel Core i5-8265U 
- **Memory:** 8 GB DDR4 RAM 
- **Storage:** 256GB SSD
- **OS:** Ubuntu Server

### Worker Node
- **CPU:** Intel Core i7-8700  
- **Memory:** 16 GB DDR4 RAM
- **Storage:** 12 TB HDD  
- **Hypervisor:** Proxmox VE
- **OS:** Ubuntu Server (running in VM)

## Core Apps & Tools


### Apps

End User Applications
<table>
    <tr>
        <th>Logo</th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/jellyfin.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://jellyfin.org/">Jellyfin</a>
    </td>
    <td>The Open-Source Media System</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://raw.githubusercontent.com/homarr-labs/dashboard-icons/a2594d147cfd8eabca0ea40474e532377aebbb44/svg/jellyseerr.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://docs.jellyseerr.dev/">Jellyseer</a>
    </td>
    <td> Requests manager for media library</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/homarr.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://homarr.dev/">Homarr</a>
    </td>
    <td> A sleek, modern dashboard</td>
    </tr>
</table> 

## Features & Services

- Jellyfin, Sonarr, Radarr, and other media services  
- QBittorrent with Gluetun for VPN routing and safely downloading torrents  
- Grafana & Prometheus monitoring and observability stack  
- Automated updates with Renovate and Flux

## Goals

- Automate and version all infrastructure and services  
- Ensure reproducibility and recoverability  
- Improve DevOps skills using real-world tools and patterns  
- Provide secure, performant, and resilient home services 