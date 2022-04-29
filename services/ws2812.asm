#define SERVICE_CLASS 0x1e3048f8
#define JD_LED_CMD_ANIMATE 0x80
#define JD_LED_REG_RO_COLOR 0x80
#define JD_LED_REG_RO_LED_COUNT 0x83

txp_color equ txp_serv0
txp_led_count equ txp_serv1
txp_variant equ txp_serv2

f_do_frame equ f_serv0

	BYTE    value_h[3]
	BYTE    value_l[3]
	BYTE    speed_h[3]
	BYTE    speed_l[3]
	BYTE    target[3]
	BYTE    tmp

.serv_init EXPAND
	PAC.PIN_WS2812 = 1 // output
ENDM

.serv_process EXPAND
	.on_rising f_do_frame, t16_1ms.5, <goto do_frame>
ENDM

.serv_prep_tx EXPAND
	if (txp_color) {
		set0 txp_color
		.set_ro_reg JD_LED_REG_RO_COLOR
		.forc i, <012>
		.mova pkt_payload[i], value_h[i]
		.endm
		.mova pkt_size, 3
		ret
	}

	if (txp_led_count) {
		set0 txp_led_count
		.set_ro_reg JD_LED_REG_RO_LED_COUNT
		.mova pkt_payload[0], 1 // 1 LED
		.mova pkt_size, 2
		ret
	}

	if (txp_variant) {
		set0 txp_variant
		.set_ro_reg JD_REG_RO_VARIANT
		.mova pkt_payload[0], 0x2 // Variant - SMD
		.mova pkt_size, 1
		ret
	}
ENDM

swap_01:
	.swapm value_h[0], value_h[1]
	.swapm value_l[0], value_l[1]
	.swapm speed_h[0], speed_h[1]
	.swapm speed_l[0], speed_l[1]
	.swapm target[0], target[1]
	ret

swap_02:
	.swapm value_h[0], value_h[2]
	.swapm value_l[0], value_l[2]
	.swapm speed_h[0], speed_h[2]
	.swapm speed_l[0], speed_l[2]
	.swapm target[0], target[2]
	ret

chidx equ 0

do_channel:
	.mova tmp, value_h[chidx]
	mov a, speed_l[chidx]
	add value_l[chidx], a
	mov a, speed_h[chidx]
	addc value_h[chidx], a
	if (CF)	{
		// overflow
		sl a
		// if speed is negative, this is normal
		ifset CF
			goto ch_speed_neg
		// otherwise we reached the target
ch_reached_target:
		clear speed_h[chidx]
		clear speed_l[chidx]
		.mova value_h[chidx], target[chidx]
		clear value_l[chidx]
		ret
	}
	if (a == 0) {
		mov a, speed_l[chidx]
		ifset ZF
			goto ch_reached_target
		mov a, speed_h[chidx]
	}
	sl a
	if (CF) {
ch_speed_neg:
		// speed < 0
		mov a, value_h[chidx]
		sub tmp, a
		ifset CF
			goto ch_reached_target // underflow
		sub a, target[chidx]
		ifset CF
			goto ch_reached_target
	} else {
		mov a, target[chidx]
		sub a, value_h[chidx]
		ifset CF
			goto ch_reached_target
	}
	ret


// Measured as:
// 0.37us / 0.89us for 0
// 0.62us / 0.63us for 1
.ws2812_byte MACRO
@@:
	set1 PA.PIN_WS2812
	sl a
	ifclear CF
	   set0 PA.PIN_WS2812
	nop
	set0 PA.PIN_WS2812
	nop
	dzsn isr0
		goto @b
	set1 isr0.3
	set1 PA.PIN_WS2812
	sl a
	ifclear CF
	   set0 PA.PIN_WS2812
	dec isr0
	set0 PA.PIN_WS2812
	ifclear PA.PIN_JACDAC
		set1 isr1.0
	nop
ENDM

do_frame:
	.callnoint do_channel
	.callnoint swap_01
	.callnoint do_channel
	.callnoint swap_01
	.callnoint swap_02
	.callnoint do_channel
	.callnoint swap_02
	// have to disable INT for bitbanging
	.disint
		.mova isr1, 0
		.mova isr0, 7
		// assume GRB order (102)
		.forc i, <102>
		mov a, value_h[i]
		.ws2812_byte
		.endm
		ifset isr1.0
			goto switch_to_rx
	engint

	goto loop

handle_channel:
	sr isr0
	sr isr1
	mov a, isr1
	sub isr0, a
	set0 frm_flags.6
	if (CF) {
		// result is negative
		neg isr0
		set1 frm_flags.6	
	}
	.mul_8x8 rx_data, isr1, isr2, isr0, pkt_payload[3]
	if (frm_flags.6) {
		// isr1:isr2 = -isr1:isr2
		not isr2 // negate high bits first
		neg isr1
		ifset ZF // isr1 was 0, so there was "carry" to isr2
			inc isr2
	}
	ret

serv_rx:
	mov a, pkt_service_command_h

	if (a == JD_HIGH_CMD) {
		mov a, pkt_service_command_l

		if (a == JD_LED_CMD_ANIMATE) {
			// ch->speed = ((to[i] - (ch->value >> 8)) * anim->speed) >> 1;
			.forc i, <012>
				mov a, pkt_payload[i]
				mov target[i], a
				mov isr0, a
				.mova isr1, value_h[i]
				call handle_channel
				.mova speed_h[i], isr2
				.mova speed_l[i], isr1
			.endm
		}

		goto rx_process_end
	}

	if (a == JD_HIGH_REG_RO_GET) {
		mov a, pkt_service_command_l

		.reg_cmp JD_LED_REG_RO_COLOR, txp_color
		.reg_cmp JD_REG_RO_VARIANT, txp_variant
		.reg_cmp JD_LED_REG_RO_LED_COUNT, txp_led_count
	}

	goto not_implemented

