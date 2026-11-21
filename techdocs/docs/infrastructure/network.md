# Network

- **Gateway:** UniFi Express 7.
- **Switch:** UniFi USW Flex 2.5G 8.
- **Ingress:** Traefik with the Gateway API. Internal services are published on a `local` gateway under the internal domain; hostnames and addresses are deliberately not recorded in this repository.
- **Off-cluster apps:** exposed through a selectorless Service, a labelled EndpointSlice and an HTTPRoute in the `external-services` namespace.
- **Serial access:** kubelab-2 and kubelab-3 each carry a USB serial adapter for an ESP32-S3 device, exposed over RFC 2217 (ports 20109 and 20110). There is no authentication or TLS on these ports, so limit them to trusted clients.
- **Overlay:** a Tailscale interface is present on kubelab-1 and kubelab-2.
