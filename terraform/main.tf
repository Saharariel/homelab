terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.2"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
resource "helm_release" "jellyfin" {
  name       = "jellyfin"
  chart      = "jellyfin"
  repository = "https://k8s-at-home.com/charts/"
  namespace  = "media"

  values = [
    file("values/jellyfin-values.yaml")
  ]
}

resource "helm_release" "radarr" {
  name       = "radarr"
  chart      = "radarr"
  repository = "https://k8s-at-home.com/charts/"
  namespace  = "media"

  values = [
    file("values/radarr-values.yaml")
  ]
}

resource "helm_release" "sonarr" {
  name       = "sonarr"
  chart      = "sonarr"
  repository = "https://k8s-at-home.com/charts/"
  namespace  = "media"

  values = [
    file("values/sonarr-values.yaml")
  ]
}

resource "helm_release" "wikijs" {
  name       = "wikijs"
  chart      = "wikijs"
  repository = "https://k8s-at-home.com/charts/"
  namespace  = "media"

  values = [
    file("values/wikijs-values.yaml")
  ]
}
