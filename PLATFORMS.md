# Supported Platforms

Swiftmiko is a from-scratch Swift port of [Netmiko](https://github.com/ktbyers/netmiko).
Every driver listed below has been translated and compiles against
Swiftmiko's `BaseConnection`/`CiscoBaseConnection` API, but **none has
yet been verified against real or emulated hardware.** The tiers
below reflect Netmiko's own testing maturity for reference — they say
nothing about Swiftmiko's current state.

## Status Legend

| Status | Meaning |
|---|---|
| ⬜ Untested | Translated and compiling; never connected to a real or emulated device |
| 🟨 In Progress | Actively being tested against GNS3/real hardware |
| ✅ Verified | Confirmed working: connect, session prep, at least one `sendCommand` round-trip |
| ⚠️ Known Issue | Tested, found broken — see linked issue |

Update this table as you work through GNS3. Everything starts ⬜.

Every driver below is registered in `SSHDispatcher.defaultConnectionFactories`
and reachable through `connectHandler` by its `deviceType` string — see
`SSHDispatcher.platforms` for the exact list, or
[`COMMON_ISSUES.md`](./COMMON_ISSUES.md) for the small number of
`deviceType` strings that exist in Netmiko but have no Swift driver
ported yet.

---

## Platforms

### Cisco Family

| Status | Platform |
|---|---|
| 🟨 | Cisco IOS |
| 🟨 | Cisco IOS-XE |
| ⬜ | Cisco IOS-XR |
| ⬜ | Cisco NX-OS |
| ⬜ | Cisco ASA |
| ⬜ | Cisco FTD |
| ⬜ | Cisco AireOS (Wireless LAN Controllers) |
| ⬜ | Cisco APIC (Linux) |
| ⬜ | Cisco S200/S300/S500 |
| ⬜ | Cisco Telepresence |
| ⬜ | Cisco Viptela |

### Juniper

| Status | Platform |
|---|---|
| ⬜ | Juniper Junos |
| ⬜ | Juniper ScreenOS |

### Arista

| Status | Platform |
|---|---|
| ⬜ | Arista vEOS |

### Linux-Family

| Status | Platform |
|---|---|
| ⬜ | Generic Linux |
| ⬜ | Corelight Linux |
| ⬜ | Cumulus VX Linux |
| ⬜ | Edgecore SONiC |
| ⬜ | F5 Linux |
| ⬜ | Open vSwitch (OVS) Linux |

### HPE / Aruba

| Status | Platform |
|---|---|
| ⬜ | HPE Comware7 |
| ⬜ | HPE ProCurve |
| ⬜ | Aruba OS Switch |
| ⬜ | Aruba AOS-CX |
| ⬜ | Aruba OS (Wireless Controllers/WAPs) |

### Huawei

| Status | Platform |
|---|---|
| ⬜ | Huawei |
| ⬜ | Huawei OLT |
| ⬜ | Huawei SmartAX |
| ⬜ | Huawei ONT |

### Dell

| Status | Platform |
|---|---|
| ⬜ | Dell OS9 (Force10) |
| ⬜ | Dell OS10 |
| ⬜ | Dell OS6 |
| ⬜ | Dell PowerConnect |
| ⬜ | Dell SONiC |
| ⬜ | Dell EMC Isilon |

### Extreme / Avaya / Brocade

| Status | Platform |
|---|---|
| ⬜ | Extreme ERS (Avaya) |
| ⬜ | Extreme MLX/NetIron (Brocade/Foundry) |
| ⬜ | Extreme TierraOS |
| ⬜ | Extreme VDX (Brocade) |
| ⬜ | Extreme VSP (Avaya) |
| ⬜ | Extreme EXOS |
| ⬜ | Extreme Wing |
| ⬜ | Extreme SLX (Brocade) |
| ⬜ | Brocade Fabric OS |

### Nokia / Alcatel

| Status | Platform |
|---|---|
| ⬜ | Nokia/Alcatel SR OS |
| ⬜ | Nokia SR Linux |
| ⬜ | Alcatel AOS6/AOS8 |

### Fortinet / Palo Alto / Check Point / Watchguard

| Status | Platform |
|---|---|
| ⬜ | Fortinet |
| ⬜ | Palo Alto PAN-OS |
| ⬜ | Check Point GAiA |
| ⬜ | Watchguard Firebox |
| ⬜ | Sophos SFOS |

### MikroTik / Ubiquiti

| Status | Platform |
|---|---|
| ⬜ | MikroTik RouterOS |
| ⬜ | MikroTik SwitchOS |
| ⬜ | Ubiquiti EdgeSwitch |
| ⬜ | Ubiquiti Unifi Switch |

### Ciena / Nokia Optical

| Status | Platform |
|---|---|
| ⬜ | Ciena SAOS |
| ⬜ | Ciena SAOS10 |
| ⬜ | Ciena Waveserver |
| ⬜ | Infinera Packet |
| ⬜ | Adva AOS FSP150 F2 & F3 |

### Everything Else

| Status | Platform |
|---|---|
| ⬜ | 6WIND TurboRouter |
| ⬜ | A10 |
| ⬜ | Accedian |
| ⬜ | Adtran OS |
| ⬜ | Alaxala AX2600S and AX3600S |
| ⬜ | Allied Telesis AlliedWare Plus |
| ⬜ | Apresia Systems AEOS |
| ⬜ | ARRIS CER |
| ⬜ | AsterFusion AsterNOS SONiC |
| ⬜ | AudioCodes Gateways & Controllers |
| ⬜ | Avara OAP800 |
| ⬜ | Aviat WTM Outdoor Radio |
| ⬜ | Bintec BOSS (Bintec/Funkwerk) |
| ⬜ | Broadcom ICOS |
| ⬜ | Calix B6 |
| ⬜ | Casa Systems CMTS |
| ⬜ | C-DOT CROS |
| ⬜ | Centec Networks |
| ⬜ | CloudGenix ION |
| ⬜ | Citrix Netscaler |
| ⬜ | Coriant |
| ⬜ | Digi TransPort Routers |
| ⬜ | Ekinops 360 |
| ⬜ | Eltex |
| ⬜ | Enterasys |
| ⬜ | Endace |
| ⬜ | Ericsson IPOS |
| ⬜ | Ericsson MINI-LINK 66XX & 63XX |
| ⬜ | Fiberstore FSOS |
| ⬜ | Fiberstore FS-OS (V2) |
| ⬜ | Fiberstore NetworkOS |
| ⬜ | Fujitsu Si-R (Fsas Technologies) |
| ⬜ | Furukawa FITELnet |
| ⬜ | Garderos GRS |
| ⬜ | Genexis Saturn SOLT33 (telnet only) |
| ⬜ | Hillstone StoneOS |
| ⬜ | Hioso OLT |
| ⬜ | Hirschmann HiOS |
| ⬜ | IIJ SEIL |
| ⬜ | IP Infusion OcNOS |
| ⬜ | Keymile |
| ⬜ | Lancom LCOS SX4 |
| ⬜ | Lancom LCOS SX5 |
| ⬜ | Maipu |
| ⬜ | Moxa EDS |
| ⬜ | MRV Communications OptiSwitch |
| ⬜ | MRV LX |
| ⬜ | NEC Univerge IX Routers |
| ⬜ | NetApp cDOT |
| ⬜ | Netgear ProSafe |
| ⬜ | NVIDIA-Mellanox |
| ⬜ | OneAccess |
| ⬜ | Optilink EOLT 9702 (telnet only) |
| ⬜ | Optilink EOLT 11444/11448 |
| ⬜ | Perle IOLAN Console Server |
| ⬜ | Pluribus |
| ⬜ | QuantaMesh |
| ⬜ | Rad ETX |
| ⬜ | Raisecom ROAP |
| ⬜ | Raisecom ROS |
| ⬜ | Ruckus ICX/FastIron |
| ⬜ | Ruijie Networks |
| ⬜ | Silver Peak VXOA |
| ⬜ | Supermicro SMIS |
| ⬜ | Teldat CIT |
| ⬜ | Telco Systems BiNOS |
| ⬜ | TPLink JetStream |
| ⬜ | Versa Networks FlexVNF |
| ⬜ | Vertiv MPH Power Distribution Units |
| ⬜ | Vyatta VyOS |
| ⬜ | Yamaha |
| ⬜ | ZPE Systems Nodegrid |
| ⬜ | ZTE ZXROS |
| ⬜ | Zyxel NOS |

---

## Supported `deviceType` Values

These are the strings to pass as `ConnectionProfile.deviceType` (or
the equivalent `device_type` key in a `.netmiko.yml`-style inventory
file). Status is not tracked per-value here — see the platform tables
above; a `deviceType` inherits its driver's test status.

### SSH
a10, accedian, adtran_os, adva_fsp150f2, adva_fsp150f3, alaxala_ax26s,
alaxala_ax36s, alcatel_aos, alcatel_sros, allied_telesis_awplus,
apresia_aeos, arista_eos, arris_cer, aruba_aoscx, aruba_os,
aruba_osswitch, aruba_procurve, asterfusion_asternos, audiocode_66,
audiocode_72, audiocode_shell, avara_aos, avaya_ers, avaya_vsp,
aviat_wtm, bintec_boss, broadcom_icos, brocade_fastiron, brocade_fos,
brocade_netiron, brocade_nos, brocade_vdx, brocade_vyos, calix_b6,
casa_cmts, cdot_cros, centec_os, checkpoint_gaia, ciena_saos,
ciena_saos10, ciena_waveserver, cisco_apic, cisco_asa, cisco_ftd,
cisco_ios, cisco_nxos, cisco_s200, cisco_s300, cisco_s500, cisco_tp,
cisco_viptela, cisco_wlc, cisco_xe, cisco_xr, cloudgenix_ion,
corelight_linux, coriant, cumulus_linux, dell_dnos9, dell_force10,
dell_isilon, dell_os10, dell_os6, dell_os9, dell_powerconnect,
dell_sonic, digi_transport, dlink_ds, edgecore_sonic, ekinops_ek360,
eltex, eltex_esr, endace, enterasys, ericsson_ipos, ericsson_mltn63,
ericsson_mltn66, extreme, extreme_ers, extreme_exos, extreme_netiron,
extreme_nos, extreme_slx, extreme_tierra, extreme_vdx, extreme_vsp,
extreme_wing, f5_linux, f5_ltm, f5_tmsh, fiberstore_fsos,
fiberstore_fsosv2, fiberstore_networkos, flexvnf, fortinet,
fujitsu_sir, furukawa_fitelnet, garderos_grs, generic,
generic_termserver, h3c_comware, hillstone_stoneos, hirschmann_hios,
hp_comware, hp_procurve, huawei, huawei_olt, huawei_ont,
huawei_smartax, huawei_smartaxmmi, huawei_vrp, huawei_vrpv8,
iij_seilos, infinera_packet, ipinfusion_ocnos, juniper, juniper_junos,
juniper_screenos, keymile, keymile_nos, lancom_lcossx4,
lancom_lcossx5, linux, maipu, mellanox, mellanox_mlnxos,
mikrotik_routeros, mikrotik_switchos, moxa_nos, mrv_lx,
mrv_optiswitch, nec_ix, netapp_cdot, netgear_prosafe, netscaler,
nokia_srl, nokia_sros, oneaccess_oneos, ovs_linux, paloalto_panos,
pluribus, quanta_mesh, rad_etx, raisecom_roap, raisecom_ros,
ruckus_fastiron, ruijie_os, silverpeak_vxoa, sixwind_os, sophos_sfos,
supermicro_smis, telcosystems_binos, teldat_cit, tplink_jetstream,
ubiquiti_edge, ubiquiti_edgerouter, ubiquiti_edgeswitch,
ubiquiti_unifiswitch, vertiv_mph, vyatta_vyos, vyos,
watchguard_fireware, yamaha, zpe_nodegrid, zte_zxros, zyxel_os

### Telnet

adtran_os_telnet, apresia_aeos_telnet, arista_eos_telnet,
aruba_procurve_telnet, audiocode_66_telnet, audiocode_72_telnet,
audiocode_shell_telnet, bintec_boss_telnet, brocade_fastiron_telnet,
brocade_netiron_telnet, calix_b6_telnet, centec_os_telnet,
ciena_saos_telnet, cisco_ios_telnet, cisco_nxos_telnet,
cisco_s200_telnet, cisco_s300_telnet, cisco_s500_telnet,
cisco_xr_telnet, dell_dnos6_telnet, dell_powerconnect_telnet,
dlink_ds_telnet, extreme_exos_telnet, extreme_netiron_telnet,
extreme_telnet, fiberstore_fsosv2_telnet, furukawa_fitelnet_telnet,
generic_telnet, generic_termserver_telnet, genexis_solt33_telnet,
hp_comware_telnet, hp_procurve_telnet, hioso_olt_telnet,
huawei_olt_telnet, huawei_ont_telnet, huawei_telnet,
infinera_packet_telnet, ipinfusion_ocnos_telnet, juniper_junos_telnet,
maipu_telnet, nec_ix_telnet, nokia_sros_telnet, oneaccess_oneos_telnet,
optilink_eolt11444_telnet, optilink_eolt9702_telnet,
paloalto_panos_telnet, rad_etx_telnet, raisecom_ros_telnet,
raisecom_telnet, ruckus_fastiron_telnet, ruijie_os_telnet,
iij_seilos_telnet, supermicro_smis_telnet, telcosystems_binos_telnet,
teldat_cit_telnet, tplink_jetstream_telnet, yamaha_telnet,
zte_zxros_telnet

### Secure Copy (SCP)

aruba_os, arista_eos, ciena_saos, cisco_asa, cisco_ios, cisco_nxos,
cisco_xe, cisco_xr, dell_os10, dell_sonic, extreme_exos, juniper_junos,
linux, nokia_sros, mikrotik_routeros, ubiquiti_edgerouter, zpe_nodegrid

### Serial

cisco_ios_serial, furukawa_fitelnet_serial

Direct console connections over a local serial port (`ConnectionProfile.host`
set to the device path, e.g. `/dev/cu.usbserial-12345`), backed by
`SerialChannel` (`Sources/SerialChannel.swift`) rather than SSH or
Telnet. Needs real hardware (or a USB-serial adapter into a real
device) to verify — there's no serial equivalent of GNS3.

---

## Testing Priority Suggestions

Given GNS3's own image availability, these are realistic first
candidates once you're ready to start flipping statuses to 🟨/✅:

1. **Cisco IOS / IOS-XE** — most widely available GNS3 images, and
   the reference implementation everything else in this project was
   built and compared against.
2. **Arista vEOS** — freely available vEOS-lab image, good second
   data point for a genuinely different vendor.
3. **Juniper Junos** — vSRX/vMX images available with a Juniper
   account; exercises the shell/CLI duality and commit lifecycle.
4. **Linux / OVS Linux** — no GNS3 image needed at all; any Ubuntu VM
   or Docker container with `openvswitch-switch` installed works,
   and validates `LinuxSSHConnection` independent of any
   network-vendor quirks.
5. **MikroTik RouterOS** — free CHR (Cloud Hosted Router) image,
   exercises the username-suffix terminal-config trick and the
   repaint-heavy output stripping.

Everything past this tier is lower priority until the core
Cisco/Arista/Juniper/Linux path is confirmed solid end to end.
