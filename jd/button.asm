#define SERVICE_CLASS 0x1473a263
#define SENSOR_SIZE 1

#define JD_BUTTON_EV_DOWN 0x01
#define JD_BUTTON_EV_UP 0x02
#define JD_BUTTON_EV_HOLD 0x81

	BYTE	t_sample
	BYTE    t_btn_hold
	BYTE    btn_down_l
	BYTE    btn_down_h

	.sensor_impl

.serv_init EXPAND
	PAPH.PIN_BTN =   1 // pullup on btn
	.mova streaming_interval, 20
ENDM

.serv_process EXPAND
	.ev_process
	.t16_chk t16_1ms, t_sample, <goto do_sample>
	.sensor_process
ENDM

.serv_prep_tx MACRO
	ifset tx_pending.txp_event
		goto ev_prep_tx
	.sensor_prep_tx
ENDM

do_sample:
	.t16_set t16_1ms, t_sample, 20
	mov a, sensor_state[0]
	ifclear PA.PIN_BTN
		goto button_active
button_inactive:
	ifset ZF // state==0
		goto loop // just keep going
	clear sensor_state[0]
		// snapshot duration
		mov a, t16_1ms
		sub a, btn_down_l
		mov btn_down_l, a
		mov a, t16_262ms
		subc a, btn_down_h
		mov btn_down_h, a

	mov a, JD_BUTTON_EV_UP
	goto ev_send
button_active:
	ifset ZF
		goto button_down
	.t16_chk t16_16ms, t_btn_hold, <goto button_hold>
	goto loop
button_hold:
	.t16_set t16_16ms, t_btn_hold, 31
	mov a, JD_BUTTON_EV_HOLD
	goto ev_send
button_down:
	.mova sensor_state[0], 1
	.disint
		.mova btn_down_l, t16_1ms
		.mova btn_down_h, t16_262ms
	engint
	.t16_set t16_16ms, t_btn_hold, 31
	mov a, JD_BUTTON_EV_DOWN
	goto ev_send

serv_rx:
	.sensor_rx

.serv_ev_payload EXPAND
	.mova pkt_size, 4
	mov a, ev_code
	mov pkt_service_command_l, a
	if (a == JD_BUTTON_EV_DOWN) {
		clear pkt_size // down event doesn't have payload
	} else if (a == JD_BUTTON_EV_UP) {
		// we snapshot final duration when emitting up
		.mova pkt_payload[0], btn_down_l
		.mova pkt_payload[1], btn_down_h
	} else {
		// hold events have duration computed on the fly
		mov a, t16_1ms
		sub a, btn_down_l
		mov pkt_payload[0], a
		mov a, t16_262ms
		subc a, btn_down_h
		mov pkt_payload[1], a
	}
ENDM

	.ev_impl