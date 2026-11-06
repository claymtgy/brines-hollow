class_name DualSenseConstants
extends RefCounted
## Sony DualSense (PS5) hardware definitions, packet constants, and trigger modes.

enum Hand {
	LEFT,   ## L2 trigger
	RIGHT   ## R2 trigger
}

enum TriggerMode {
	OFF = 0x05,             ## Standard linear unassisted trigger
	FEEDBACK = 0x21,        ## Continuous resistance starting at position
	WEAPON = 0x22,          ## Two-stage trigger with mechanical break point
	GALLOPING = 0x23,       ## Rhythmic galloping pulsation
	MACHINE = 0x25,         ## Mechanical stepping / rapid vibration
	VIBRATION = 0x26,       ## Slope frequency vibration
	BOW = 0x27              ## Increasing tension curve (bow draw)
}

const USB_REPORT_ID := 0x02
const BT_REPORT_ID := 0x31

# Vendor & Product IDs
const SONY_VENDOR_ID := 0x054C
const DUALSENSE_PID := 0x0CE6
const DUALSENSE_EDGE_PID := 0x0DF2

# DualSenseX local UDP port
const DUALSENSEX_UDP_PORT := 6969
