# UNVT Hitchhiker

**A portable web map server that rides on your personal hotspot.**

---

## What is UNVT Hitchhiker?

UNVT Hitchhiker is a *yet another* implementation of **UNVT Portable**: a minimalist, ultra-low-power **portable web map server** designed to run on devices such as the **Raspberry Pi Zero W** and connect via a **personal mobile hotspot** (e.g. iPhone Personal Hotspot).

Instead of owning network infrastructure, UNVT Hitchhiker deliberately *hitches a ride* on existing personal connectivity. By combining static, cloud-native geospatial data (such as **PMTiles**) with a lightweight web stack, it enables anyone to **carry, host, and share maps wherever a phone signal exists**.

In short:

> You don’t need a big ship.
> Just hitch a ride — and bring a map.

---

## Design Principles

* **Personal first**: Uses personal hotspots instead of dedicated networks
* **Ultra-lightweight**: Designed for Raspberry Pi Zero W–class hardware
* **Static by design**: Static files, no heavy backend services
* **Cloud-native formats**: PMTiles and other range-request–friendly formats
* **Portable & reproducible**: Easy to rebuild, reflash, and redeploy

---

## Default System Configuration

These defaults are intentionally simple and explicit.

### Machine

* **Hostname**: `hitchhiker.local`

### User Account

* **Username**: `hitchhiker`
* **Password**: `hitchhiker`

> ⚠️ Change these credentials in real deployments.

### Wi-Fi Network

UNVT Hitchhiker connects to an existing Wi-Fi network provided by a mobile device.

* **SSID**: `vectortiles`
* **Password**: `vectortiles`

This is typically an iPhone Personal Hotspot, but any equivalent hotspot works.

---

## Web Stack

### Web Server

* **Caddy**

  * Automatic HTTPS (when applicable)
  * Simple configuration
  * Single binary

### Document Root

```
/var/hitchhiker
```

This directory serves as the **DocumentRoot** for all web content.

### Map Library

* **MapLibre GL JS**

  * Always uses the **latest stable version**
  * Installed directly into `/var/hitchhiker`
  * No build step required for basic usage

Static assets (HTML, CSS, JS, PMTiles) live together under this directory.

---

## Repository Structure (Conceptual)

```
.
├── install.sh            # Installer script (pipe-to-shell)
├── caddy/
│   └── Caddyfile         # Caddy configuration
├── www/
│   ├── index.html        # Map entry point
│   ├── style.json        # MapLibre style
│   └── pmtiles/          # PMTiles data
└── README.md
```

---

## Installation

UNVT Hitchhiker is installed using a **pipe-to-shell** installer for maximum portability and minimal friction.

```sh
curl -fsSL https://raw.githubusercontent.com/UNVT/hitchhiker/main/install.sh | sh
```

The installer:

* Installs required system packages
* Sets up Caddy
* Creates `/var/hitchhiker`
* Downloads the latest MapLibre GL JS
* Configures the system for immediate use

> The goal is not perfection, but **fast, repeatable setup**.

---

## Relationship to UNVT Portable

UNVT Hitchhiker is:

* ✔ A **valid UNVT Portable implementation**
* ✔ Optimized for **personal connectivity**
* ✔ Focused on **static web maps**

It intentionally avoids:

* Running its own access point
* Heavy GIS backends
* Complex orchestration

This makes it suitable for **training, demonstrations, workshops, and field experimentation**.

---

## Intended Use Cases

* Geospatial capacity building
* Workshops and Dojo-style learning
* Field demos with minimal infrastructure
* Emergency or constrained-network scenarios
* Personal experimentation with cloud-native geospatial stacks

---

## What UNVT Hitchhiker is NOT

* ❌ A high-availability production server
* ❌ A replacement for enterprise GIS infrastructure
* ❌ A device that provides its own network

UNVT Hitchhiker is a **tool for thinking, learning, and sharing**.

---

## Operating System

* **Raspberry Pi OS Trixie Lite (32-bit)**

This project assumes a clean installation of Raspberry Pi OS Trixie Lite (32-bit) as the base operating system.

---

## License

**CC0 1.0 Universal (Public Domain Dedication)**

UNVT Hitchhiker is released under CC0. You are free to use, modify, distribute, and reuse the contents of this repository without restriction.
