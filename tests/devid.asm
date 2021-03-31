IDSIZE equ 8

fill_id:
	a = packet_buffer+4+IDSIZE-1
	mov lb@memidx, a
	.mova tmp0, IDSIZE
@@:
	mov a, tmp0
	call get_id
	idxm memidx, a
	dec lb@memidx
	dzsn tmp0
	goto @B
	ret

check_id:
	a = packet_buffer+4+IDSIZE-1
	mov lb@memidx, a
	.mova tmp0, IDSIZE
@@:
	mov a, tmp0
	call get_id
	mov tmp1, a
	idxm a, memidx
	ceqsn a, tmp1
	ret 0
	dec lb@memidx
	dzsn tmp0
	goto @B
	ret 1

// requires a=1...8
get_id:
	pcadd a
.IFDEF RELEASE
	.User_Roll 8 BYTE, "genid.bat", "ids.txt"
.ELSE
	ret 0x01
	ret 0x23
	ret 0x45
	ret 0x67
	ret 0x89
	ret 0xab
	ret 0xcd
	ret 0xef
.ENDIF