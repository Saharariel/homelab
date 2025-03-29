terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.13.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.4.1"
    }
  }
}

provider "kubernetes" {
  host                   = "https://kubernetes.default.svc"
  cluster_ca_certificate = file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
  token                  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")
}

provider "helm" {
  kubernetes {
    host                   = "https://kubernetes.default.svc"
    cluster_ca_certificate = file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
    token                  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")
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
