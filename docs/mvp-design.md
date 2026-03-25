# MVP Design

## Package name

- `luci-app-openclash-assistant`

## User story

As a soft-router / OpenClash user,
I want one page that tells me whether my environment looks healthy and which operating mode is likely safer,
so I can avoid common Fake-IP, DNS, TUN, and IPv6 mistakes.

## MVP features

### 1. Health snapshot

Show:

- OpenClash installed
- OpenClash enabled
- OpenClash process running
- config directory presence
- number of config files found
- presence of key dependencies
- nftables / firewall4 hints

### 2. Scenario-based advice

User sets:

- deployment role
- preferred proxy mode
- needs IPv6
- has exposed LAN services
- uses Tailscale or similar overlay networking
- needs gaming-device compatibility
- prefers low-maintenance operation

Assistant returns:

- recommended profile
- risk level
- likely pitfalls
- next-step checklist

## LuCI architecture

### Frontend

- `htdocs/luci-static/resources/view/openclash-assistant/status.js`

### Menu

- `root/usr/share/luci/menu.d/luci-app-openclash-assistant.json`

### ACL

- `root/usr/share/rpcd/acl.d/luci-app-openclash-assistant.json`

### Backend helper

- `root/usr/libexec/openclash-assistant/diag.sh`

### UCI config

- `root/etc/config/openclash-assistant`

## Out of scope for MVP

- automatic OpenClash config rewriting
- auto-fixing firewall or DNS state
- full log parser UI
- subscription management
- dashboard embedding

## Suggested next iteration

- redact-and-export debug summary
- fake-ip compatibility checklist generator
- SmartDNS / MosDNS conflict detector
- config backup diff view
