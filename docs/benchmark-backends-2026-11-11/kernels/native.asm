
/tmp/zgrep-backends-20261111-3ahjbzi8/explain/native.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <first_zero>:
       0:	55                   	push   rbp
       1:	48 89 e5             	mov    rbp,rsp
       4:	53                   	push   rbx
       5:	48 83 e4 e0          	and    rsp,0xffffffffffffffe0
       9:	48 83 ec 40          	sub    rsp,0x40
       d:	48 89 3c 24          	mov    QWORD PTR [rsp],rdi
      11:	48 89 74 24 08       	mov    QWORD PTR [rsp+0x8],rsi
      16:	48 89 7c 24 10       	mov    QWORD PTR [rsp+0x10],rdi
      1b:	48 8b 44 24 10       	mov    rax,QWORD PTR [rsp+0x10]
      20:	48 8d 10             	lea    rdx,[rax]
      23:	48 89 f0             	mov    rax,rsi
      26:	48 83 e8 00          	sub    rax,0x0
      2a:	48 89 54 24 18       	mov    QWORD PTR [rsp+0x18],rdx
      2f:	48 89 44 24 20       	mov    QWORD PTR [rsp+0x20],rax
      34:	48 89 74 24 28       	mov    QWORD PTR [rsp+0x28],rsi
      39:	48 8d 44 24 30       	lea    rax,[rsp+0x30]
      3e:	48 8b 54 24 18       	mov    rdx,QWORD PTR [rsp+0x18]
      43:	48 8b 5c 24 20       	mov    rbx,QWORD PTR [rsp+0x20]
      48:	31 c9                	xor    ecx,ecx
      4a:	e8 00 00 00 00       	call   4f <first_zero+0x4f>
      4f:	80 7c 24 38 00       	cmp    BYTE PTR [rsp+0x38],0x0
      54:	0f 84 0a 00 00 00    	je     64 <first_zero+0x64>
      5a:	48 8b 44 24 30       	mov    rax,QWORD PTR [rsp+0x30]
      5f:	e9 0a 00 00 00       	jmp    6e <first_zero+0x6e>
      64:	48 8b 44 24 28       	mov    rax,QWORD PTR [rsp+0x28]
      69:	e9 00 00 00 00       	jmp    6e <first_zero+0x6e>
      6e:	48 8d 65 f8          	lea    rsp,[rbp-0x8]
      72:	5b                   	pop    rbx
      73:	5d                   	pop    rbp
      74:	c3                   	ret
	...

00000000000000a0 <mem.findScalar__anon_189>:
      a0:	55                   	push   rbp
      a1:	48 89 e5             	mov    rbp,rsp
      a4:	48 83 ec 50          	sub    rsp,0x50
      a8:	48 89 04 24          	mov    QWORD PTR [rsp],rax
      ac:	48 89 54 24 08       	mov    QWORD PTR [rsp+0x8],rdx
      b1:	48 89 5c 24 10       	mov    QWORD PTR [rsp+0x10],rbx
      b6:	88 4c 24 38          	mov    BYTE PTR [rsp+0x38],cl
      ba:	48 89 54 24 18       	mov    QWORD PTR [rsp+0x18],rdx
      bf:	48 89 5c 24 20       	mov    QWORD PTR [rsp+0x20],rbx
      c4:	88 4c 24 39          	mov    BYTE PTR [rsp+0x39],cl
      c8:	48 8d 44 24 28       	lea    rax,[rsp+0x28]
      cd:	48 8b 54 24 18       	mov    rdx,QWORD PTR [rsp+0x18]
      d2:	48 8b 5c 24 20       	mov    rbx,QWORD PTR [rsp+0x20]
      d7:	31 c9                	xor    ecx,ecx
      d9:	40 8a 74 24 39       	mov    sil,BYTE PTR [rsp+0x39]
      de:	e8 00 00 00 00       	call   e3 <mem.findScalar__anon_189+0x43>
      e3:	48 8b 04 24          	mov    rax,QWORD PTR [rsp]
      e7:	c5 fa 6f 44 24 28    	vmovdqu xmm0,XMMWORD PTR [rsp+0x28]
      ed:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
      f1:	48 89 ec             	mov    rsp,rbp
      f4:	5d                   	pop    rbp
      f5:	c3                   	ret
	...

0000000000000120 <mem.findScalarPos__anon_195>:
     120:	55                   	push   rbp
     121:	48 89 e5             	mov    rbp,rsp
     124:	41 57                	push   r15
     126:	41 56                	push   r14
     128:	41 55                	push   r13
     12a:	41 54                	push   r12
     12c:	41 53                	push   r11
     12e:	48 81 ec 28 04 00 00 	sub    rsp,0x428
     135:	48 89 84 24 a0 01 00 	mov    QWORD PTR [rsp+0x1a0],rax
     13c:	00 
     13d:	48 89 94 24 a8 01 00 	mov    QWORD PTR [rsp+0x1a8],rdx
     144:	00 
     145:	48 89 9c 24 b0 01 00 	mov    QWORD PTR [rsp+0x1b0],rbx
     14c:	00 
     14d:	48 89 8c 24 b8 01 00 	mov    QWORD PTR [rsp+0x1b8],rcx
     154:	00 
     155:	40 88 b4 24 ca 03 00 	mov    BYTE PTR [rsp+0x3ca],sil
     15c:	00 
     15d:	48 89 94 24 c0 01 00 	mov    QWORD PTR [rsp+0x1c0],rdx
     164:	00 
     165:	48 89 9c 24 c8 01 00 	mov    QWORD PTR [rsp+0x1c8],rbx
     16c:	00 
     16d:	48 8b 84 24 c8 01 00 	mov    rax,QWORD PTR [rsp+0x1c8]
     174:	00 
     175:	48 89 ca             	mov    rdx,rcx
     178:	48 39 c2             	cmp    rdx,rax
     17b:	0f 82 1c 00 00 00    	jb     19d <mem.findScalarPos__anon_195+0x7d>
     181:	48 8b 84 24 a0 01 00 	mov    rax,QWORD PTR [rsp+0x1a0]
     188:	00 
     189:	48 c7 c2 00 00 00 00 	mov    rdx,0x0
     190:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
     194:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
     198:	e9 b9 12 00 00       	jmp    1456 <mem.findScalarPos__anon_195+0x1336>
     19d:	e9 00 00 00 00       	jmp    1a2 <mem.findScalarPos__anon_195+0x82>
     1a2:	48 89 8c 24 d0 01 00 	mov    QWORD PTR [rsp+0x1d0],rcx
     1a9:	00 
     1aa:	40 88 b4 24 cb 03 00 	mov    BYTE PTR [rsp+0x3cb],sil
     1b1:	00 
     1b2:	e8 00 00 00 00       	call   1b7 <mem.findScalarPos__anon_195+0x97>
     1b7:	a8 01                	test   al,0x1
     1b9:	0f 84 a0 11 00 00    	je     135f <mem.findScalarPos__anon_195+0x123f>
     1bf:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     1c6:	00 
     1c7:	48 83 c0 40          	add    rax,0x40
     1cb:	48 8b 94 24 c8 01 00 	mov    rdx,QWORD PTR [rsp+0x1c8]
     1d2:	00 
     1d3:	48 39 d0             	cmp    rax,rdx
     1d6:	0f 83 50 09 00 00    	jae    b2c <mem.findScalarPos__anon_195+0xa0c>
     1dc:	c4 e2 7d 78 84 24 cb 	vpbroadcastb ymm0,BYTE PTR [rsp+0x3cb]
     1e3:	03 00 00 
     1e6:	c5 fe 7f 04 24       	vmovdqu YMMWORD PTR [rsp],ymm0
     1eb:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     1f2:	00 
     1f3:	c5 fa 6f 8c 24 c0 01 	vmovdqu xmm1,XMMWORD PTR [rsp+0x1c0]
     1fa:	00 00 
     1fc:	c5 fa 7f 8c 24 d8 01 	vmovdqu XMMWORD PTR [rsp+0x1d8],xmm1
     203:	00 00 
     205:	48 8b 94 24 d8 01 00 	mov    rdx,QWORD PTR [rsp+0x1d8]
     20c:	00 
     20d:	48 8d 1c 02          	lea    rbx,[rdx+rax*1]
     211:	c5 fe 6f 0b          	vmovdqu ymm1,YMMWORD PTR [rbx]
     215:	c5 fe 7f 8c 24 e8 01 	vmovdqu YMMWORD PTR [rsp+0x1e8],ymm1
     21c:	00 00 
     21e:	0f b6 84 24 e8 01 00 	movzx  eax,BYTE PTR [rsp+0x1e8]
     225:	00 
     226:	0f b6 94 24 e9 01 00 	movzx  edx,BYTE PTR [rsp+0x1e9]
     22d:	00 
     22e:	0f b6 9c 24 ea 01 00 	movzx  ebx,BYTE PTR [rsp+0x1ea]
     235:	00 
     236:	0f b6 8c 24 eb 01 00 	movzx  ecx,BYTE PTR [rsp+0x1eb]
     23d:	00 
     23e:	0f b6 b4 24 ec 01 00 	movzx  esi,BYTE PTR [rsp+0x1ec]
     245:	00 
     246:	0f b6 bc 24 ed 01 00 	movzx  edi,BYTE PTR [rsp+0x1ed]
     24d:	00 
     24e:	44 0f b6 84 24 ee 01 	movzx  r8d,BYTE PTR [rsp+0x1ee]
     255:	00 00 
     257:	44 0f b6 8c 24 ef 01 	movzx  r9d,BYTE PTR [rsp+0x1ef]
     25e:	00 00 
     260:	44 0f b6 94 24 f0 01 	movzx  r10d,BYTE PTR [rsp+0x1f0]
     267:	00 00 
     269:	44 0f b6 9c 24 f1 01 	movzx  r11d,BYTE PTR [rsp+0x1f1]
     270:	00 00 
     272:	44 0f b6 a4 24 f2 01 	movzx  r12d,BYTE PTR [rsp+0x1f2]
     279:	00 00 
     27b:	44 0f b6 ac 24 f3 01 	movzx  r13d,BYTE PTR [rsp+0x1f3]
     282:	00 00 
     284:	44 0f b6 b4 24 f4 01 	movzx  r14d,BYTE PTR [rsp+0x1f4]
     28b:	00 00 
     28d:	44 0f b6 bc 24 f5 01 	movzx  r15d,BYTE PTR [rsp+0x1f5]
     294:	00 00 
     296:	88 84 24 cc 03 00 00 	mov    BYTE PTR [rsp+0x3cc],al
     29d:	0f b6 84 24 f6 01 00 	movzx  eax,BYTE PTR [rsp+0x1f6]
     2a4:	00 
     2a5:	88 84 24 cd 03 00 00 	mov    BYTE PTR [rsp+0x3cd],al
     2ac:	0f b6 84 24 f7 01 00 	movzx  eax,BYTE PTR [rsp+0x1f7]
     2b3:	00 
     2b4:	88 84 24 ce 03 00 00 	mov    BYTE PTR [rsp+0x3ce],al
     2bb:	0f b6 84 24 f8 01 00 	movzx  eax,BYTE PTR [rsp+0x1f8]
     2c2:	00 
     2c3:	88 84 24 cf 03 00 00 	mov    BYTE PTR [rsp+0x3cf],al
     2ca:	0f b6 84 24 f9 01 00 	movzx  eax,BYTE PTR [rsp+0x1f9]
     2d1:	00 
     2d2:	88 84 24 d0 03 00 00 	mov    BYTE PTR [rsp+0x3d0],al
     2d9:	0f b6 84 24 fa 01 00 	movzx  eax,BYTE PTR [rsp+0x1fa]
     2e0:	00 
     2e1:	88 84 24 d1 03 00 00 	mov    BYTE PTR [rsp+0x3d1],al
     2e8:	0f b6 84 24 fb 01 00 	movzx  eax,BYTE PTR [rsp+0x1fb]
     2ef:	00 
     2f0:	88 84 24 d2 03 00 00 	mov    BYTE PTR [rsp+0x3d2],al
     2f7:	0f b6 84 24 fc 01 00 	movzx  eax,BYTE PTR [rsp+0x1fc]
     2fe:	00 
     2ff:	88 84 24 d3 03 00 00 	mov    BYTE PTR [rsp+0x3d3],al
     306:	0f b6 84 24 fd 01 00 	movzx  eax,BYTE PTR [rsp+0x1fd]
     30d:	00 
     30e:	88 84 24 d4 03 00 00 	mov    BYTE PTR [rsp+0x3d4],al
     315:	0f b6 84 24 fe 01 00 	movzx  eax,BYTE PTR [rsp+0x1fe]
     31c:	00 
     31d:	88 84 24 d5 03 00 00 	mov    BYTE PTR [rsp+0x3d5],al
     324:	0f b6 84 24 ff 01 00 	movzx  eax,BYTE PTR [rsp+0x1ff]
     32b:	00 
     32c:	88 84 24 d6 03 00 00 	mov    BYTE PTR [rsp+0x3d6],al
     333:	0f b6 84 24 00 02 00 	movzx  eax,BYTE PTR [rsp+0x200]
     33a:	00 
     33b:	88 84 24 d7 03 00 00 	mov    BYTE PTR [rsp+0x3d7],al
     342:	0f b6 84 24 01 02 00 	movzx  eax,BYTE PTR [rsp+0x201]
     349:	00 
     34a:	88 84 24 d8 03 00 00 	mov    BYTE PTR [rsp+0x3d8],al
     351:	0f b6 84 24 02 02 00 	movzx  eax,BYTE PTR [rsp+0x202]
     358:	00 
     359:	88 84 24 d9 03 00 00 	mov    BYTE PTR [rsp+0x3d9],al
     360:	0f b6 84 24 03 02 00 	movzx  eax,BYTE PTR [rsp+0x203]
     367:	00 
     368:	88 84 24 da 03 00 00 	mov    BYTE PTR [rsp+0x3da],al
     36f:	0f b6 84 24 04 02 00 	movzx  eax,BYTE PTR [rsp+0x204]
     376:	00 
     377:	88 84 24 db 03 00 00 	mov    BYTE PTR [rsp+0x3db],al
     37e:	0f b6 84 24 05 02 00 	movzx  eax,BYTE PTR [rsp+0x205]
     385:	00 
     386:	88 84 24 dc 03 00 00 	mov    BYTE PTR [rsp+0x3dc],al
     38d:	0f b6 84 24 06 02 00 	movzx  eax,BYTE PTR [rsp+0x206]
     394:	00 
     395:	88 84 24 dd 03 00 00 	mov    BYTE PTR [rsp+0x3dd],al
     39c:	0f b6 84 24 07 02 00 	movzx  eax,BYTE PTR [rsp+0x207]
     3a3:	00 
     3a4:	88 84 24 de 03 00 00 	mov    BYTE PTR [rsp+0x3de],al
     3ab:	40 88 bc 24 df 03 00 	mov    BYTE PTR [rsp+0x3df],dil
     3b2:	00 
     3b3:	88 94 24 e0 03 00 00 	mov    BYTE PTR [rsp+0x3e0],dl
     3ba:	48 8d 54 24 20       	lea    rdx,[rsp+0x20]
     3bf:	48 89 94 24 08 02 00 	mov    QWORD PTR [rsp+0x208],rdx
     3c6:	00 
     3c7:	48 8b bc 24 08 02 00 	mov    rdi,QWORD PTR [rsp+0x208]
     3ce:	00 
     3cf:	40 88 b4 24 e1 03 00 	mov    BYTE PTR [rsp+0x3e1],sil
     3d6:	00 
     3d7:	48 8d 94 24 cc 03 00 	lea    rdx,[rsp+0x3cc]
     3de:	00 
     3df:	48 89 94 24 10 02 00 	mov    QWORD PTR [rsp+0x210],rdx
     3e6:	00 
     3e7:	48 8b b4 24 10 02 00 	mov    rsi,QWORD PTR [rsp+0x210]
     3ee:	00 
     3ef:	88 8c 24 e2 03 00 00 	mov    BYTE PTR [rsp+0x3e2],cl
     3f6:	48 89 84 24 18 02 00 	mov    QWORD PTR [rsp+0x218],rax
     3fd:	00 
     3fe:	48 8b 8c 24 18 02 00 	mov    rcx,QWORD PTR [rsp+0x218]
     405:	00 
     406:	48 c7 c1 01 00 00 00 	mov    rcx,0x1
     40d:	f3 a4                	rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
     40f:	8a 84 24 e0 03 00 00 	mov    al,BYTE PTR [rsp+0x3e0]
     416:	88 44 24 21          	mov    BYTE PTR [rsp+0x21],al
     41a:	88 5c 24 22          	mov    BYTE PTR [rsp+0x22],bl
     41e:	8a 84 24 e2 03 00 00 	mov    al,BYTE PTR [rsp+0x3e2]
     425:	88 44 24 23          	mov    BYTE PTR [rsp+0x23],al
     429:	8a 84 24 e1 03 00 00 	mov    al,BYTE PTR [rsp+0x3e1]
     430:	88 44 24 24          	mov    BYTE PTR [rsp+0x24],al
     434:	8a 84 24 df 03 00 00 	mov    al,BYTE PTR [rsp+0x3df]
     43b:	88 44 24 25          	mov    BYTE PTR [rsp+0x25],al
     43f:	44 88 44 24 26       	mov    BYTE PTR [rsp+0x26],r8b
     444:	44 88 4c 24 27       	mov    BYTE PTR [rsp+0x27],r9b
     449:	44 88 54 24 28       	mov    BYTE PTR [rsp+0x28],r10b
     44e:	44 88 5c 24 29       	mov    BYTE PTR [rsp+0x29],r11b
     453:	44 88 64 24 2a       	mov    BYTE PTR [rsp+0x2a],r12b
     458:	44 88 6c 24 2b       	mov    BYTE PTR [rsp+0x2b],r13b
     45d:	44 88 74 24 2c       	mov    BYTE PTR [rsp+0x2c],r14b
     462:	44 88 7c 24 2d       	mov    BYTE PTR [rsp+0x2d],r15b
     467:	8a 84 24 cd 03 00 00 	mov    al,BYTE PTR [rsp+0x3cd]
     46e:	88 44 24 2e          	mov    BYTE PTR [rsp+0x2e],al
     472:	8a 84 24 ce 03 00 00 	mov    al,BYTE PTR [rsp+0x3ce]
     479:	88 44 24 2f          	mov    BYTE PTR [rsp+0x2f],al
     47d:	8a 84 24 cf 03 00 00 	mov    al,BYTE PTR [rsp+0x3cf]
     484:	88 44 24 30          	mov    BYTE PTR [rsp+0x30],al
     488:	8a 84 24 d0 03 00 00 	mov    al,BYTE PTR [rsp+0x3d0]
     48f:	88 44 24 31          	mov    BYTE PTR [rsp+0x31],al
     493:	8a 84 24 d1 03 00 00 	mov    al,BYTE PTR [rsp+0x3d1]
     49a:	88 44 24 32          	mov    BYTE PTR [rsp+0x32],al
     49e:	8a 84 24 d2 03 00 00 	mov    al,BYTE PTR [rsp+0x3d2]
     4a5:	88 44 24 33          	mov    BYTE PTR [rsp+0x33],al
     4a9:	8a 84 24 d3 03 00 00 	mov    al,BYTE PTR [rsp+0x3d3]
     4b0:	88 44 24 34          	mov    BYTE PTR [rsp+0x34],al
     4b4:	8a 84 24 d4 03 00 00 	mov    al,BYTE PTR [rsp+0x3d4]
     4bb:	88 44 24 35          	mov    BYTE PTR [rsp+0x35],al
     4bf:	8a 84 24 d5 03 00 00 	mov    al,BYTE PTR [rsp+0x3d5]
     4c6:	88 44 24 36          	mov    BYTE PTR [rsp+0x36],al
     4ca:	8a 84 24 d6 03 00 00 	mov    al,BYTE PTR [rsp+0x3d6]
     4d1:	88 44 24 37          	mov    BYTE PTR [rsp+0x37],al
     4d5:	8a 84 24 d7 03 00 00 	mov    al,BYTE PTR [rsp+0x3d7]
     4dc:	88 44 24 38          	mov    BYTE PTR [rsp+0x38],al
     4e0:	8a 84 24 d8 03 00 00 	mov    al,BYTE PTR [rsp+0x3d8]
     4e7:	88 44 24 39          	mov    BYTE PTR [rsp+0x39],al
     4eb:	8a 84 24 d9 03 00 00 	mov    al,BYTE PTR [rsp+0x3d9]
     4f2:	88 44 24 3a          	mov    BYTE PTR [rsp+0x3a],al
     4f6:	8a 84 24 da 03 00 00 	mov    al,BYTE PTR [rsp+0x3da]
     4fd:	88 44 24 3b          	mov    BYTE PTR [rsp+0x3b],al
     501:	8a 84 24 db 03 00 00 	mov    al,BYTE PTR [rsp+0x3db]
     508:	88 44 24 3c          	mov    BYTE PTR [rsp+0x3c],al
     50c:	8a 84 24 dc 03 00 00 	mov    al,BYTE PTR [rsp+0x3dc]
     513:	88 44 24 3d          	mov    BYTE PTR [rsp+0x3d],al
     517:	8a 84 24 dd 03 00 00 	mov    al,BYTE PTR [rsp+0x3dd]
     51e:	88 44 24 3e          	mov    BYTE PTR [rsp+0x3e],al
     522:	8a 84 24 de 03 00 00 	mov    al,BYTE PTR [rsp+0x3de]
     529:	88 44 24 3f          	mov    BYTE PTR [rsp+0x3f],al
     52d:	c5 fe 6f 4c 24 20    	vmovdqu ymm1,YMMWORD PTR [rsp+0x20]
     533:	c5 fe 7f 4c 24 40    	vmovdqu YMMWORD PTR [rsp+0x40],ymm1
     539:	48 c7 84 24 20 02 00 	mov    QWORD PTR [rsp+0x220],0x0
     540:	00 00 00 00 00 
     545:	48 8b 84 24 20 02 00 	mov    rax,QWORD PTR [rsp+0x220]
     54c:	00 
     54d:	0f b6 54 04 20       	movzx  edx,BYTE PTR [rsp+rax*1+0x20]
     552:	c5 fe 7f 44 24 60    	vmovdqu YMMWORD PTR [rsp+0x60],ymm0
     558:	0f b6 5c 04 60       	movzx  ebx,BYTE PTR [rsp+rax*1+0x60]
     55d:	38 da                	cmp    dl,bl
     55f:	48 8d 94 24 98 03 00 	lea    rdx,[rsp+0x398]
     566:	00 
     567:	0f 94 c3             	sete   bl
     56a:	8b 0a                	mov    ecx,DWORD PTR [rdx]
     56c:	89 ce                	mov    esi,ecx
     56e:	0f b3 c6             	btr    esi,eax
     571:	0f ab c1             	bts    ecx,eax
     574:	f6 c3 01             	test   bl,0x1
     577:	0f 44 ce             	cmove  ecx,esi
     57a:	89 0a                	mov    DWORD PTR [rdx],ecx
     57c:	48 83 f8 1f          	cmp    rax,0x1f
     580:	0f 85 0c 00 00 00    	jne    592 <mem.findScalarPos__anon_195+0x472>
     586:	8b 84 24 98 03 00 00 	mov    eax,DWORD PTR [rsp+0x398]
     58d:	e9 11 00 00 00       	jmp    5a3 <mem.findScalarPos__anon_195+0x483>
     592:	48 83 c0 01          	add    rax,0x1
     596:	48 89 84 24 20 02 00 	mov    QWORD PTR [rsp+0x220],rax
     59d:	00 
     59e:	e9 a2 ff ff ff       	jmp    545 <mem.findScalarPos__anon_195+0x425>
     5a3:	89 84 24 9c 03 00 00 	mov    DWORD PTR [rsp+0x39c],eax
     5aa:	85 c0                	test   eax,eax
     5ac:	0f 84 6f 00 00 00    	je     621 <mem.findScalarPos__anon_195+0x501>
     5b2:	48 8b 94 24 d0 01 00 	mov    rdx,QWORD PTR [rsp+0x1d0]
     5b9:	00 
     5ba:	89 84 24 a0 03 00 00 	mov    DWORD PTR [rsp+0x3a0],eax
     5c1:	48 89 94 24 28 02 00 	mov    QWORD PTR [rsp+0x228],rdx
     5c8:	00 
     5c9:	8b 84 24 a0 03 00 00 	mov    eax,DWORD PTR [rsp+0x3a0]
     5d0:	e8 00 00 00 00       	call   5d5 <mem.findScalarPos__anon_195+0x4b5>
     5d5:	66 89 84 24 bc 03 00 	mov    WORD PTR [rsp+0x3bc],ax
     5dc:	00 
     5dd:	8a 94 24 bc 03 00 00 	mov    dl,BYTE PTR [rsp+0x3bc]
     5e4:	0f b6 d2             	movzx  edx,dl
     5e7:	48 01 94 24 28 02 00 	add    QWORD PTR [rsp+0x228],rdx
     5ee:	00 
     5ef:	48 8b 84 24 28 02 00 	mov    rax,QWORD PTR [rsp+0x228]
     5f6:	00 
     5f7:	48 89 84 24 30 02 00 	mov    QWORD PTR [rsp+0x230],rax
     5fe:	00 
     5ff:	c6 84 24 38 02 00 00 	mov    BYTE PTR [rsp+0x238],0x1
     606:	01 
     607:	48 8b 84 24 a0 01 00 	mov    rax,QWORD PTR [rsp+0x1a0]
     60e:	00 
     60f:	c5 fa 6f 84 24 30 02 	vmovdqu xmm0,XMMWORD PTR [rsp+0x230]
     616:	00 00 
     618:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
     61c:	e9 35 0e 00 00       	jmp    1456 <mem.findScalarPos__anon_195+0x1336>
     621:	e9 00 00 00 00       	jmp    626 <mem.findScalarPos__anon_195+0x506>
     626:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     62d:	00 
     62e:	48 83 c0 20          	add    rax,0x20
     632:	48 89 84 24 d0 01 00 	mov    QWORD PTR [rsp+0x1d0],rax
     639:	00 
     63a:	90                   	nop
     63b:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     642:	00 
     643:	c5 fa 6f 8c 24 c0 01 	vmovdqu xmm1,XMMWORD PTR [rsp+0x1c0]
     64a:	00 00 
     64c:	c5 fa 7f 8c 24 40 02 	vmovdqu XMMWORD PTR [rsp+0x240],xmm1
     653:	00 00 
     655:	48 8b 94 24 40 02 00 	mov    rdx,QWORD PTR [rsp+0x240]
     65c:	00 
     65d:	48 8d 1c 02          	lea    rbx,[rdx+rax*1]
     661:	c5 fe 6f 0b          	vmovdqu ymm1,YMMWORD PTR [rbx]
     665:	c5 fe 7f 8c 24 50 02 	vmovdqu YMMWORD PTR [rsp+0x250],ymm1
     66c:	00 00 
     66e:	0f b6 84 24 50 02 00 	movzx  eax,BYTE PTR [rsp+0x250]
     675:	00 
     676:	0f b6 94 24 51 02 00 	movzx  edx,BYTE PTR [rsp+0x251]
     67d:	00 
     67e:	0f b6 9c 24 52 02 00 	movzx  ebx,BYTE PTR [rsp+0x252]
     685:	00 
     686:	0f b6 8c 24 53 02 00 	movzx  ecx,BYTE PTR [rsp+0x253]
     68d:	00 
     68e:	0f b6 b4 24 54 02 00 	movzx  esi,BYTE PTR [rsp+0x254]
     695:	00 
     696:	0f b6 bc 24 55 02 00 	movzx  edi,BYTE PTR [rsp+0x255]
     69d:	00 
     69e:	44 0f b6 84 24 56 02 	movzx  r8d,BYTE PTR [rsp+0x256]
     6a5:	00 00 
     6a7:	44 0f b6 8c 24 57 02 	movzx  r9d,BYTE PTR [rsp+0x257]
     6ae:	00 00 
     6b0:	44 0f b6 94 24 58 02 	movzx  r10d,BYTE PTR [rsp+0x258]
     6b7:	00 00 
     6b9:	44 0f b6 9c 24 59 02 	movzx  r11d,BYTE PTR [rsp+0x259]
     6c0:	00 00 
     6c2:	44 0f b6 a4 24 5a 02 	movzx  r12d,BYTE PTR [rsp+0x25a]
     6c9:	00 00 
     6cb:	44 0f b6 ac 24 5b 02 	movzx  r13d,BYTE PTR [rsp+0x25b]
     6d2:	00 00 
     6d4:	44 0f b6 b4 24 5c 02 	movzx  r14d,BYTE PTR [rsp+0x25c]
     6db:	00 00 
     6dd:	44 0f b6 bc 24 5d 02 	movzx  r15d,BYTE PTR [rsp+0x25d]
     6e4:	00 00 
     6e6:	88 84 24 e3 03 00 00 	mov    BYTE PTR [rsp+0x3e3],al
     6ed:	0f b6 84 24 5e 02 00 	movzx  eax,BYTE PTR [rsp+0x25e]
     6f4:	00 
     6f5:	88 84 24 e4 03 00 00 	mov    BYTE PTR [rsp+0x3e4],al
     6fc:	0f b6 84 24 5f 02 00 	movzx  eax,BYTE PTR [rsp+0x25f]
     703:	00 
     704:	88 84 24 e5 03 00 00 	mov    BYTE PTR [rsp+0x3e5],al
     70b:	0f b6 84 24 60 02 00 	movzx  eax,BYTE PTR [rsp+0x260]
     712:	00 
     713:	88 84 24 e6 03 00 00 	mov    BYTE PTR [rsp+0x3e6],al
     71a:	0f b6 84 24 61 02 00 	movzx  eax,BYTE PTR [rsp+0x261]
     721:	00 
     722:	88 84 24 e7 03 00 00 	mov    BYTE PTR [rsp+0x3e7],al
     729:	0f b6 84 24 62 02 00 	movzx  eax,BYTE PTR [rsp+0x262]
     730:	00 
     731:	88 84 24 e8 03 00 00 	mov    BYTE PTR [rsp+0x3e8],al
     738:	0f b6 84 24 63 02 00 	movzx  eax,BYTE PTR [rsp+0x263]
     73f:	00 
     740:	88 84 24 e9 03 00 00 	mov    BYTE PTR [rsp+0x3e9],al
     747:	0f b6 84 24 64 02 00 	movzx  eax,BYTE PTR [rsp+0x264]
     74e:	00 
     74f:	88 84 24 ea 03 00 00 	mov    BYTE PTR [rsp+0x3ea],al
     756:	0f b6 84 24 65 02 00 	movzx  eax,BYTE PTR [rsp+0x265]
     75d:	00 
     75e:	88 84 24 eb 03 00 00 	mov    BYTE PTR [rsp+0x3eb],al
     765:	0f b6 84 24 66 02 00 	movzx  eax,BYTE PTR [rsp+0x266]
     76c:	00 
     76d:	88 84 24 ec 03 00 00 	mov    BYTE PTR [rsp+0x3ec],al
     774:	0f b6 84 24 67 02 00 	movzx  eax,BYTE PTR [rsp+0x267]
     77b:	00 
     77c:	88 84 24 ed 03 00 00 	mov    BYTE PTR [rsp+0x3ed],al
     783:	0f b6 84 24 68 02 00 	movzx  eax,BYTE PTR [rsp+0x268]
     78a:	00 
     78b:	88 84 24 ee 03 00 00 	mov    BYTE PTR [rsp+0x3ee],al
     792:	0f b6 84 24 69 02 00 	movzx  eax,BYTE PTR [rsp+0x269]
     799:	00 
     79a:	88 84 24 ef 03 00 00 	mov    BYTE PTR [rsp+0x3ef],al
     7a1:	0f b6 84 24 6a 02 00 	movzx  eax,BYTE PTR [rsp+0x26a]
     7a8:	00 
     7a9:	88 84 24 f0 03 00 00 	mov    BYTE PTR [rsp+0x3f0],al
     7b0:	0f b6 84 24 6b 02 00 	movzx  eax,BYTE PTR [rsp+0x26b]
     7b7:	00 
     7b8:	88 84 24 f1 03 00 00 	mov    BYTE PTR [rsp+0x3f1],al
     7bf:	0f b6 84 24 6c 02 00 	movzx  eax,BYTE PTR [rsp+0x26c]
     7c6:	00 
     7c7:	88 84 24 f2 03 00 00 	mov    BYTE PTR [rsp+0x3f2],al
     7ce:	0f b6 84 24 6d 02 00 	movzx  eax,BYTE PTR [rsp+0x26d]
     7d5:	00 
     7d6:	88 84 24 f3 03 00 00 	mov    BYTE PTR [rsp+0x3f3],al
     7dd:	0f b6 84 24 6e 02 00 	movzx  eax,BYTE PTR [rsp+0x26e]
     7e4:	00 
     7e5:	88 84 24 f4 03 00 00 	mov    BYTE PTR [rsp+0x3f4],al
     7ec:	0f b6 84 24 6f 02 00 	movzx  eax,BYTE PTR [rsp+0x26f]
     7f3:	00 
     7f4:	88 84 24 f5 03 00 00 	mov    BYTE PTR [rsp+0x3f5],al
     7fb:	40 88 bc 24 f6 03 00 	mov    BYTE PTR [rsp+0x3f6],dil
     802:	00 
     803:	88 94 24 f7 03 00 00 	mov    BYTE PTR [rsp+0x3f7],dl
     80a:	48 8d 94 24 80 00 00 	lea    rdx,[rsp+0x80]
     811:	00 
     812:	48 89 94 24 70 02 00 	mov    QWORD PTR [rsp+0x270],rdx
     819:	00 
     81a:	48 8b bc 24 70 02 00 	mov    rdi,QWORD PTR [rsp+0x270]
     821:	00 
     822:	40 88 b4 24 f8 03 00 	mov    BYTE PTR [rsp+0x3f8],sil
     829:	00 
     82a:	48 8d 94 24 e3 03 00 	lea    rdx,[rsp+0x3e3]
     831:	00 
     832:	48 89 94 24 78 02 00 	mov    QWORD PTR [rsp+0x278],rdx
     839:	00 
     83a:	48 8b b4 24 78 02 00 	mov    rsi,QWORD PTR [rsp+0x278]
     841:	00 
     842:	88 8c 24 f9 03 00 00 	mov    BYTE PTR [rsp+0x3f9],cl
     849:	48 89 84 24 80 02 00 	mov    QWORD PTR [rsp+0x280],rax
     850:	00 
     851:	48 8b 8c 24 80 02 00 	mov    rcx,QWORD PTR [rsp+0x280]
     858:	00 
     859:	48 c7 c1 01 00 00 00 	mov    rcx,0x1
     860:	f3 a4                	rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
     862:	8a 84 24 f7 03 00 00 	mov    al,BYTE PTR [rsp+0x3f7]
     869:	88 84 24 81 00 00 00 	mov    BYTE PTR [rsp+0x81],al
     870:	88 9c 24 82 00 00 00 	mov    BYTE PTR [rsp+0x82],bl
     877:	8a 84 24 f9 03 00 00 	mov    al,BYTE PTR [rsp+0x3f9]
     87e:	88 84 24 83 00 00 00 	mov    BYTE PTR [rsp+0x83],al
     885:	8a 84 24 f8 03 00 00 	mov    al,BYTE PTR [rsp+0x3f8]
     88c:	88 84 24 84 00 00 00 	mov    BYTE PTR [rsp+0x84],al
     893:	8a 84 24 f6 03 00 00 	mov    al,BYTE PTR [rsp+0x3f6]
     89a:	88 84 24 85 00 00 00 	mov    BYTE PTR [rsp+0x85],al
     8a1:	44 88 84 24 86 00 00 	mov    BYTE PTR [rsp+0x86],r8b
     8a8:	00 
     8a9:	44 88 8c 24 87 00 00 	mov    BYTE PTR [rsp+0x87],r9b
     8b0:	00 
     8b1:	44 88 94 24 88 00 00 	mov    BYTE PTR [rsp+0x88],r10b
     8b8:	00 
     8b9:	44 88 9c 24 89 00 00 	mov    BYTE PTR [rsp+0x89],r11b
     8c0:	00 
     8c1:	44 88 a4 24 8a 00 00 	mov    BYTE PTR [rsp+0x8a],r12b
     8c8:	00 
     8c9:	44 88 ac 24 8b 00 00 	mov    BYTE PTR [rsp+0x8b],r13b
     8d0:	00 
     8d1:	44 88 b4 24 8c 00 00 	mov    BYTE PTR [rsp+0x8c],r14b
     8d8:	00 
     8d9:	44 88 bc 24 8d 00 00 	mov    BYTE PTR [rsp+0x8d],r15b
     8e0:	00 
     8e1:	8a 84 24 e4 03 00 00 	mov    al,BYTE PTR [rsp+0x3e4]
     8e8:	88 84 24 8e 00 00 00 	mov    BYTE PTR [rsp+0x8e],al
     8ef:	8a 84 24 e5 03 00 00 	mov    al,BYTE PTR [rsp+0x3e5]
     8f6:	88 84 24 8f 00 00 00 	mov    BYTE PTR [rsp+0x8f],al
     8fd:	8a 84 24 e6 03 00 00 	mov    al,BYTE PTR [rsp+0x3e6]
     904:	88 84 24 90 00 00 00 	mov    BYTE PTR [rsp+0x90],al
     90b:	8a 84 24 e7 03 00 00 	mov    al,BYTE PTR [rsp+0x3e7]
     912:	88 84 24 91 00 00 00 	mov    BYTE PTR [rsp+0x91],al
     919:	8a 84 24 e8 03 00 00 	mov    al,BYTE PTR [rsp+0x3e8]
     920:	88 84 24 92 00 00 00 	mov    BYTE PTR [rsp+0x92],al
     927:	8a 84 24 e9 03 00 00 	mov    al,BYTE PTR [rsp+0x3e9]
     92e:	88 84 24 93 00 00 00 	mov    BYTE PTR [rsp+0x93],al
     935:	8a 84 24 ea 03 00 00 	mov    al,BYTE PTR [rsp+0x3ea]
     93c:	88 84 24 94 00 00 00 	mov    BYTE PTR [rsp+0x94],al
     943:	8a 84 24 eb 03 00 00 	mov    al,BYTE PTR [rsp+0x3eb]
     94a:	88 84 24 95 00 00 00 	mov    BYTE PTR [rsp+0x95],al
     951:	8a 84 24 ec 03 00 00 	mov    al,BYTE PTR [rsp+0x3ec]
     958:	88 84 24 96 00 00 00 	mov    BYTE PTR [rsp+0x96],al
     95f:	8a 84 24 ed 03 00 00 	mov    al,BYTE PTR [rsp+0x3ed]
     966:	88 84 24 97 00 00 00 	mov    BYTE PTR [rsp+0x97],al
     96d:	8a 84 24 ee 03 00 00 	mov    al,BYTE PTR [rsp+0x3ee]
     974:	88 84 24 98 00 00 00 	mov    BYTE PTR [rsp+0x98],al
     97b:	8a 84 24 ef 03 00 00 	mov    al,BYTE PTR [rsp+0x3ef]
     982:	88 84 24 99 00 00 00 	mov    BYTE PTR [rsp+0x99],al
     989:	8a 84 24 f0 03 00 00 	mov    al,BYTE PTR [rsp+0x3f0]
     990:	88 84 24 9a 00 00 00 	mov    BYTE PTR [rsp+0x9a],al
     997:	8a 84 24 f1 03 00 00 	mov    al,BYTE PTR [rsp+0x3f1]
     99e:	88 84 24 9b 00 00 00 	mov    BYTE PTR [rsp+0x9b],al
     9a5:	8a 84 24 f2 03 00 00 	mov    al,BYTE PTR [rsp+0x3f2]
     9ac:	88 84 24 9c 00 00 00 	mov    BYTE PTR [rsp+0x9c],al
     9b3:	8a 84 24 f3 03 00 00 	mov    al,BYTE PTR [rsp+0x3f3]
     9ba:	88 84 24 9d 00 00 00 	mov    BYTE PTR [rsp+0x9d],al
     9c1:	8a 84 24 f4 03 00 00 	mov    al,BYTE PTR [rsp+0x3f4]
     9c8:	88 84 24 9e 00 00 00 	mov    BYTE PTR [rsp+0x9e],al
     9cf:	8a 84 24 f5 03 00 00 	mov    al,BYTE PTR [rsp+0x3f5]
     9d6:	88 84 24 9f 00 00 00 	mov    BYTE PTR [rsp+0x9f],al
     9dd:	c5 fe 6f 8c 24 80 00 	vmovdqu ymm1,YMMWORD PTR [rsp+0x80]
     9e4:	00 00 
     9e6:	c5 fe 7f 8c 24 a0 00 	vmovdqu YMMWORD PTR [rsp+0xa0],ymm1
     9ed:	00 00 
     9ef:	48 c7 84 24 88 02 00 	mov    QWORD PTR [rsp+0x288],0x0
     9f6:	00 00 00 00 00 
     9fb:	48 8b 84 24 88 02 00 	mov    rax,QWORD PTR [rsp+0x288]
     a02:	00 
     a03:	0f b6 94 04 80 00 00 	movzx  edx,BYTE PTR [rsp+rax*1+0x80]
     a0a:	00 
     a0b:	c5 fe 7f 84 24 c0 00 	vmovdqu YMMWORD PTR [rsp+0xc0],ymm0
     a12:	00 00 
     a14:	0f b6 9c 04 c0 00 00 	movzx  ebx,BYTE PTR [rsp+rax*1+0xc0]
     a1b:	00 
     a1c:	38 da                	cmp    dl,bl
     a1e:	48 8d 94 24 a4 03 00 	lea    rdx,[rsp+0x3a4]
     a25:	00 
     a26:	0f 94 c3             	sete   bl
     a29:	8b 0a                	mov    ecx,DWORD PTR [rdx]
     a2b:	89 ce                	mov    esi,ecx
     a2d:	0f b3 c6             	btr    esi,eax
     a30:	0f ab c1             	bts    ecx,eax
     a33:	f6 c3 01             	test   bl,0x1
     a36:	0f 44 ce             	cmove  ecx,esi
     a39:	89 0a                	mov    DWORD PTR [rdx],ecx
     a3b:	48 83 f8 1f          	cmp    rax,0x1f
     a3f:	0f 85 0c 00 00 00    	jne    a51 <mem.findScalarPos__anon_195+0x931>
     a45:	8b 84 24 a4 03 00 00 	mov    eax,DWORD PTR [rsp+0x3a4]
     a4c:	e9 11 00 00 00       	jmp    a62 <mem.findScalarPos__anon_195+0x942>
     a51:	48 83 c0 01          	add    rax,0x1
     a55:	48 89 84 24 88 02 00 	mov    QWORD PTR [rsp+0x288],rax
     a5c:	00 
     a5d:	e9 99 ff ff ff       	jmp    9fb <mem.findScalarPos__anon_195+0x8db>
     a62:	89 84 24 a8 03 00 00 	mov    DWORD PTR [rsp+0x3a8],eax
     a69:	85 c0                	test   eax,eax
     a6b:	0f 84 6f 00 00 00    	je     ae0 <mem.findScalarPos__anon_195+0x9c0>
     a71:	48 8b 94 24 d0 01 00 	mov    rdx,QWORD PTR [rsp+0x1d0]
     a78:	00 
     a79:	89 84 24 ac 03 00 00 	mov    DWORD PTR [rsp+0x3ac],eax
     a80:	48 89 94 24 90 02 00 	mov    QWORD PTR [rsp+0x290],rdx
     a87:	00 
     a88:	8b 84 24 ac 03 00 00 	mov    eax,DWORD PTR [rsp+0x3ac]
     a8f:	e8 00 00 00 00       	call   a94 <mem.findScalarPos__anon_195+0x974>
     a94:	66 89 84 24 be 03 00 	mov    WORD PTR [rsp+0x3be],ax
     a9b:	00 
     a9c:	8a 94 24 be 03 00 00 	mov    dl,BYTE PTR [rsp+0x3be]
     aa3:	0f b6 d2             	movzx  edx,dl
     aa6:	48 01 94 24 90 02 00 	add    QWORD PTR [rsp+0x290],rdx
     aad:	00 
     aae:	48 8b 84 24 90 02 00 	mov    rax,QWORD PTR [rsp+0x290]
     ab5:	00 
     ab6:	48 89 84 24 98 02 00 	mov    QWORD PTR [rsp+0x298],rax
     abd:	00 
     abe:	c6 84 24 a0 02 00 00 	mov    BYTE PTR [rsp+0x2a0],0x1
     ac5:	01 
     ac6:	48 8b 84 24 a0 01 00 	mov    rax,QWORD PTR [rsp+0x1a0]
     acd:	00 
     ace:	c5 fa 6f 84 24 98 02 	vmovdqu xmm0,XMMWORD PTR [rsp+0x298]
     ad5:	00 00 
     ad7:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
     adb:	e9 76 09 00 00       	jmp    1456 <mem.findScalarPos__anon_195+0x1336>
     ae0:	e9 00 00 00 00       	jmp    ae5 <mem.findScalarPos__anon_195+0x9c5>
     ae5:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     aec:	00 
     aed:	48 83 c0 20          	add    rax,0x20
     af1:	48 89 84 24 d0 01 00 	mov    QWORD PTR [rsp+0x1d0],rax
     af8:	00 
     af9:	90                   	nop
     afa:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     b01:	00 
     b02:	48 83 c0 40          	add    rax,0x40
     b06:	48 8b 94 24 c8 01 00 	mov    rdx,QWORD PTR [rsp+0x1c8]
     b0d:	00 
     b0e:	48 39 d0             	cmp    rax,rdx
     b11:	0f 82 05 00 00 00    	jb     b1c <mem.findScalarPos__anon_195+0x9fc>
     b17:	e9 0b 00 00 00       	jmp    b27 <mem.findScalarPos__anon_195+0xa07>
     b1c:	e9 00 00 00 00       	jmp    b21 <mem.findScalarPos__anon_195+0xa01>
     b21:	90                   	nop
     b22:	e9 c4 f6 ff ff       	jmp    1eb <mem.findScalarPos__anon_195+0xcb>
     b27:	e9 05 00 00 00       	jmp    b31 <mem.findScalarPos__anon_195+0xa11>
     b2c:	e9 00 00 00 00       	jmp    b31 <mem.findScalarPos__anon_195+0xa11>
     b31:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     b38:	00 
     b39:	48 83 c0 20          	add    rax,0x20
     b3d:	48 8b 94 24 c8 01 00 	mov    rdx,QWORD PTR [rsp+0x1c8]
     b44:	00 
     b45:	48 39 d0             	cmp    rax,rdx
     b48:	0f 83 d6 04 00 00    	jae    1024 <mem.findScalarPos__anon_195+0xf04>
     b4e:	c4 e2 7d 78 84 24 cb 	vpbroadcastb ymm0,BYTE PTR [rsp+0x3cb]
     b55:	03 00 00 
     b58:	c5 fe 7f 84 24 e0 00 	vmovdqu YMMWORD PTR [rsp+0xe0],ymm0
     b5f:	00 00 
     b61:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
     b68:	00 
     b69:	c5 fa 6f 8c 24 c0 01 	vmovdqu xmm1,XMMWORD PTR [rsp+0x1c0]
     b70:	00 00 
     b72:	c5 fa 7f 8c 24 a8 02 	vmovdqu XMMWORD PTR [rsp+0x2a8],xmm1
     b79:	00 00 
     b7b:	48 8b 94 24 a8 02 00 	mov    rdx,QWORD PTR [rsp+0x2a8]
     b82:	00 
     b83:	48 8d 1c 02          	lea    rbx,[rdx+rax*1]
     b87:	c5 fe 6f 0b          	vmovdqu ymm1,YMMWORD PTR [rbx]
     b8b:	c5 fe 7f 8c 24 b8 02 	vmovdqu YMMWORD PTR [rsp+0x2b8],ymm1
     b92:	00 00 
     b94:	0f b6 84 24 b8 02 00 	movzx  eax,BYTE PTR [rsp+0x2b8]
     b9b:	00 
     b9c:	0f b6 94 24 b9 02 00 	movzx  edx,BYTE PTR [rsp+0x2b9]
     ba3:	00 
     ba4:	0f b6 9c 24 ba 02 00 	movzx  ebx,BYTE PTR [rsp+0x2ba]
     bab:	00 
     bac:	0f b6 8c 24 bb 02 00 	movzx  ecx,BYTE PTR [rsp+0x2bb]
     bb3:	00 
     bb4:	0f b6 b4 24 bc 02 00 	movzx  esi,BYTE PTR [rsp+0x2bc]
     bbb:	00 
     bbc:	0f b6 bc 24 bd 02 00 	movzx  edi,BYTE PTR [rsp+0x2bd]
     bc3:	00 
     bc4:	44 0f b6 84 24 be 02 	movzx  r8d,BYTE PTR [rsp+0x2be]
     bcb:	00 00 
     bcd:	44 0f b6 8c 24 bf 02 	movzx  r9d,BYTE PTR [rsp+0x2bf]
     bd4:	00 00 
     bd6:	44 0f b6 94 24 c0 02 	movzx  r10d,BYTE PTR [rsp+0x2c0]
     bdd:	00 00 
     bdf:	44 0f b6 9c 24 c1 02 	movzx  r11d,BYTE PTR [rsp+0x2c1]
     be6:	00 00 
     be8:	44 0f b6 a4 24 c2 02 	movzx  r12d,BYTE PTR [rsp+0x2c2]
     bef:	00 00 
     bf1:	44 0f b6 ac 24 c3 02 	movzx  r13d,BYTE PTR [rsp+0x2c3]
     bf8:	00 00 
     bfa:	44 0f b6 b4 24 c4 02 	movzx  r14d,BYTE PTR [rsp+0x2c4]
     c01:	00 00 
     c03:	44 0f b6 bc 24 c5 02 	movzx  r15d,BYTE PTR [rsp+0x2c5]
     c0a:	00 00 
     c0c:	88 84 24 fa 03 00 00 	mov    BYTE PTR [rsp+0x3fa],al
     c13:	0f b6 84 24 c6 02 00 	movzx  eax,BYTE PTR [rsp+0x2c6]
     c1a:	00 
     c1b:	88 84 24 fb 03 00 00 	mov    BYTE PTR [rsp+0x3fb],al
     c22:	0f b6 84 24 c7 02 00 	movzx  eax,BYTE PTR [rsp+0x2c7]
     c29:	00 
     c2a:	88 84 24 fc 03 00 00 	mov    BYTE PTR [rsp+0x3fc],al
     c31:	0f b6 84 24 c8 02 00 	movzx  eax,BYTE PTR [rsp+0x2c8]
     c38:	00 
     c39:	88 84 24 fd 03 00 00 	mov    BYTE PTR [rsp+0x3fd],al
     c40:	0f b6 84 24 c9 02 00 	movzx  eax,BYTE PTR [rsp+0x2c9]
     c47:	00 
     c48:	88 84 24 fe 03 00 00 	mov    BYTE PTR [rsp+0x3fe],al
     c4f:	0f b6 84 24 ca 02 00 	movzx  eax,BYTE PTR [rsp+0x2ca]
     c56:	00 
     c57:	88 84 24 ff 03 00 00 	mov    BYTE PTR [rsp+0x3ff],al
     c5e:	0f b6 84 24 cb 02 00 	movzx  eax,BYTE PTR [rsp+0x2cb]
     c65:	00 
     c66:	88 84 24 00 04 00 00 	mov    BYTE PTR [rsp+0x400],al
     c6d:	0f b6 84 24 cc 02 00 	movzx  eax,BYTE PTR [rsp+0x2cc]
     c74:	00 
     c75:	88 84 24 01 04 00 00 	mov    BYTE PTR [rsp+0x401],al
     c7c:	0f b6 84 24 cd 02 00 	movzx  eax,BYTE PTR [rsp+0x2cd]
     c83:	00 
     c84:	88 84 24 02 04 00 00 	mov    BYTE PTR [rsp+0x402],al
     c8b:	0f b6 84 24 ce 02 00 	movzx  eax,BYTE PTR [rsp+0x2ce]
     c92:	00 
     c93:	88 84 24 03 04 00 00 	mov    BYTE PTR [rsp+0x403],al
     c9a:	0f b6 84 24 cf 02 00 	movzx  eax,BYTE PTR [rsp+0x2cf]
     ca1:	00 
     ca2:	88 84 24 04 04 00 00 	mov    BYTE PTR [rsp+0x404],al
     ca9:	0f b6 84 24 d0 02 00 	movzx  eax,BYTE PTR [rsp+0x2d0]
     cb0:	00 
     cb1:	88 84 24 05 04 00 00 	mov    BYTE PTR [rsp+0x405],al
     cb8:	0f b6 84 24 d1 02 00 	movzx  eax,BYTE PTR [rsp+0x2d1]
     cbf:	00 
     cc0:	88 84 24 06 04 00 00 	mov    BYTE PTR [rsp+0x406],al
     cc7:	0f b6 84 24 d2 02 00 	movzx  eax,BYTE PTR [rsp+0x2d2]
     cce:	00 
     ccf:	88 84 24 07 04 00 00 	mov    BYTE PTR [rsp+0x407],al
     cd6:	0f b6 84 24 d3 02 00 	movzx  eax,BYTE PTR [rsp+0x2d3]
     cdd:	00 
     cde:	88 84 24 08 04 00 00 	mov    BYTE PTR [rsp+0x408],al
     ce5:	0f b6 84 24 d4 02 00 	movzx  eax,BYTE PTR [rsp+0x2d4]
     cec:	00 
     ced:	88 84 24 09 04 00 00 	mov    BYTE PTR [rsp+0x409],al
     cf4:	0f b6 84 24 d5 02 00 	movzx  eax,BYTE PTR [rsp+0x2d5]
     cfb:	00 
     cfc:	88 84 24 0a 04 00 00 	mov    BYTE PTR [rsp+0x40a],al
     d03:	0f b6 84 24 d6 02 00 	movzx  eax,BYTE PTR [rsp+0x2d6]
     d0a:	00 
     d0b:	88 84 24 0b 04 00 00 	mov    BYTE PTR [rsp+0x40b],al
     d12:	0f b6 84 24 d7 02 00 	movzx  eax,BYTE PTR [rsp+0x2d7]
     d19:	00 
     d1a:	88 84 24 0c 04 00 00 	mov    BYTE PTR [rsp+0x40c],al
     d21:	40 88 bc 24 0d 04 00 	mov    BYTE PTR [rsp+0x40d],dil
     d28:	00 
     d29:	88 94 24 0e 04 00 00 	mov    BYTE PTR [rsp+0x40e],dl
     d30:	48 8d 94 24 00 01 00 	lea    rdx,[rsp+0x100]
     d37:	00 
     d38:	48 89 94 24 d8 02 00 	mov    QWORD PTR [rsp+0x2d8],rdx
     d3f:	00 
     d40:	48 8b bc 24 d8 02 00 	mov    rdi,QWORD PTR [rsp+0x2d8]
     d47:	00 
     d48:	40 88 b4 24 0f 04 00 	mov    BYTE PTR [rsp+0x40f],sil
     d4f:	00 
     d50:	48 8d 94 24 fa 03 00 	lea    rdx,[rsp+0x3fa]
     d57:	00 
     d58:	48 89 94 24 e0 02 00 	mov    QWORD PTR [rsp+0x2e0],rdx
     d5f:	00 
     d60:	48 8b b4 24 e0 02 00 	mov    rsi,QWORD PTR [rsp+0x2e0]
     d67:	00 
     d68:	88 8c 24 10 04 00 00 	mov    BYTE PTR [rsp+0x410],cl
     d6f:	48 89 84 24 e8 02 00 	mov    QWORD PTR [rsp+0x2e8],rax
     d76:	00 
     d77:	48 8b 8c 24 e8 02 00 	mov    rcx,QWORD PTR [rsp+0x2e8]
     d7e:	00 
     d7f:	48 c7 c1 01 00 00 00 	mov    rcx,0x1
     d86:	f3 a4                	rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
     d88:	8a 84 24 0e 04 00 00 	mov    al,BYTE PTR [rsp+0x40e]
     d8f:	88 84 24 01 01 00 00 	mov    BYTE PTR [rsp+0x101],al
     d96:	88 9c 24 02 01 00 00 	mov    BYTE PTR [rsp+0x102],bl
     d9d:	8a 84 24 10 04 00 00 	mov    al,BYTE PTR [rsp+0x410]
     da4:	88 84 24 03 01 00 00 	mov    BYTE PTR [rsp+0x103],al
     dab:	8a 84 24 0f 04 00 00 	mov    al,BYTE PTR [rsp+0x40f]
     db2:	88 84 24 04 01 00 00 	mov    BYTE PTR [rsp+0x104],al
     db9:	8a 84 24 0d 04 00 00 	mov    al,BYTE PTR [rsp+0x40d]
     dc0:	88 84 24 05 01 00 00 	mov    BYTE PTR [rsp+0x105],al
     dc7:	44 88 84 24 06 01 00 	mov    BYTE PTR [rsp+0x106],r8b
     dce:	00 
     dcf:	44 88 8c 24 07 01 00 	mov    BYTE PTR [rsp+0x107],r9b
     dd6:	00 
     dd7:	44 88 94 24 08 01 00 	mov    BYTE PTR [rsp+0x108],r10b
     dde:	00 
     ddf:	44 88 9c 24 09 01 00 	mov    BYTE PTR [rsp+0x109],r11b
     de6:	00 
     de7:	44 88 a4 24 0a 01 00 	mov    BYTE PTR [rsp+0x10a],r12b
     dee:	00 
     def:	44 88 ac 24 0b 01 00 	mov    BYTE PTR [rsp+0x10b],r13b
     df6:	00 
     df7:	44 88 b4 24 0c 01 00 	mov    BYTE PTR [rsp+0x10c],r14b
     dfe:	00 
     dff:	44 88 bc 24 0d 01 00 	mov    BYTE PTR [rsp+0x10d],r15b
     e06:	00 
     e07:	8a 84 24 fb 03 00 00 	mov    al,BYTE PTR [rsp+0x3fb]
     e0e:	88 84 24 0e 01 00 00 	mov    BYTE PTR [rsp+0x10e],al
     e15:	8a 84 24 fc 03 00 00 	mov    al,BYTE PTR [rsp+0x3fc]
     e1c:	88 84 24 0f 01 00 00 	mov    BYTE PTR [rsp+0x10f],al
     e23:	8a 84 24 fd 03 00 00 	mov    al,BYTE PTR [rsp+0x3fd]
     e2a:	88 84 24 10 01 00 00 	mov    BYTE PTR [rsp+0x110],al
     e31:	8a 84 24 fe 03 00 00 	mov    al,BYTE PTR [rsp+0x3fe]
     e38:	88 84 24 11 01 00 00 	mov    BYTE PTR [rsp+0x111],al
     e3f:	8a 84 24 ff 03 00 00 	mov    al,BYTE PTR [rsp+0x3ff]
     e46:	88 84 24 12 01 00 00 	mov    BYTE PTR [rsp+0x112],al
     e4d:	8a 84 24 00 04 00 00 	mov    al,BYTE PTR [rsp+0x400]
     e54:	88 84 24 13 01 00 00 	mov    BYTE PTR [rsp+0x113],al
     e5b:	8a 84 24 01 04 00 00 	mov    al,BYTE PTR [rsp+0x401]
     e62:	88 84 24 14 01 00 00 	mov    BYTE PTR [rsp+0x114],al
     e69:	8a 84 24 02 04 00 00 	mov    al,BYTE PTR [rsp+0x402]
     e70:	88 84 24 15 01 00 00 	mov    BYTE PTR [rsp+0x115],al
     e77:	8a 84 24 03 04 00 00 	mov    al,BYTE PTR [rsp+0x403]
     e7e:	88 84 24 16 01 00 00 	mov    BYTE PTR [rsp+0x116],al
     e85:	8a 84 24 04 04 00 00 	mov    al,BYTE PTR [rsp+0x404]
     e8c:	88 84 24 17 01 00 00 	mov    BYTE PTR [rsp+0x117],al
     e93:	8a 84 24 05 04 00 00 	mov    al,BYTE PTR [rsp+0x405]
     e9a:	88 84 24 18 01 00 00 	mov    BYTE PTR [rsp+0x118],al
     ea1:	8a 84 24 06 04 00 00 	mov    al,BYTE PTR [rsp+0x406]
     ea8:	88 84 24 19 01 00 00 	mov    BYTE PTR [rsp+0x119],al
     eaf:	8a 84 24 07 04 00 00 	mov    al,BYTE PTR [rsp+0x407]
     eb6:	88 84 24 1a 01 00 00 	mov    BYTE PTR [rsp+0x11a],al
     ebd:	8a 84 24 08 04 00 00 	mov    al,BYTE PTR [rsp+0x408]
     ec4:	88 84 24 1b 01 00 00 	mov    BYTE PTR [rsp+0x11b],al
     ecb:	8a 84 24 09 04 00 00 	mov    al,BYTE PTR [rsp+0x409]
     ed2:	88 84 24 1c 01 00 00 	mov    BYTE PTR [rsp+0x11c],al
     ed9:	8a 84 24 0a 04 00 00 	mov    al,BYTE PTR [rsp+0x40a]
     ee0:	88 84 24 1d 01 00 00 	mov    BYTE PTR [rsp+0x11d],al
     ee7:	8a 84 24 0b 04 00 00 	mov    al,BYTE PTR [rsp+0x40b]
     eee:	88 84 24 1e 01 00 00 	mov    BYTE PTR [rsp+0x11e],al
     ef5:	8a 84 24 0c 04 00 00 	mov    al,BYTE PTR [rsp+0x40c]
     efc:	88 84 24 1f 01 00 00 	mov    BYTE PTR [rsp+0x11f],al
     f03:	c5 fe 6f 8c 24 00 01 	vmovdqu ymm1,YMMWORD PTR [rsp+0x100]
     f0a:	00 00 
     f0c:	c5 fe 7f 8c 24 20 01 	vmovdqu YMMWORD PTR [rsp+0x120],ymm1
     f13:	00 00 
     f15:	48 c7 84 24 f0 02 00 	mov    QWORD PTR [rsp+0x2f0],0x0
     f1c:	00 00 00 00 00 
     f21:	48 8b 84 24 f0 02 00 	mov    rax,QWORD PTR [rsp+0x2f0]
     f28:	00 
     f29:	0f b6 94 04 00 01 00 	movzx  edx,BYTE PTR [rsp+rax*1+0x100]
     f30:	00 
     f31:	c5 fe 7f 84 24 40 01 	vmovdqu YMMWORD PTR [rsp+0x140],ymm0
     f38:	00 00 
     f3a:	0f b6 9c 04 40 01 00 	movzx  ebx,BYTE PTR [rsp+rax*1+0x140]
     f41:	00 
     f42:	38 da                	cmp    dl,bl
     f44:	48 8d 94 24 b0 03 00 	lea    rdx,[rsp+0x3b0]
     f4b:	00 
     f4c:	0f 94 c3             	sete   bl
     f4f:	8b 0a                	mov    ecx,DWORD PTR [rdx]
     f51:	89 ce                	mov    esi,ecx
     f53:	0f b3 c6             	btr    esi,eax
     f56:	0f ab c1             	bts    ecx,eax
     f59:	f6 c3 01             	test   bl,0x1
     f5c:	0f 44 ce             	cmove  ecx,esi
     f5f:	89 0a                	mov    DWORD PTR [rdx],ecx
     f61:	48 83 f8 1f          	cmp    rax,0x1f
     f65:	0f 85 0c 00 00 00    	jne    f77 <mem.findScalarPos__anon_195+0xe57>
     f6b:	8b 84 24 b0 03 00 00 	mov    eax,DWORD PTR [rsp+0x3b0]
     f72:	e9 11 00 00 00       	jmp    f88 <mem.findScalarPos__anon_195+0xe68>
     f77:	48 83 c0 01          	add    rax,0x1
     f7b:	48 89 84 24 f0 02 00 	mov    QWORD PTR [rsp+0x2f0],rax
     f82:	00 
     f83:	e9 99 ff ff ff       	jmp    f21 <mem.findScalarPos__anon_195+0xe01>
     f88:	89 84 24 b4 03 00 00 	mov    DWORD PTR [rsp+0x3b4],eax
     f8f:	85 c0                	test   eax,eax
     f91:	0f 84 6f 00 00 00    	je     1006 <mem.findScalarPos__anon_195+0xee6>
     f97:	48 8b 94 24 d0 01 00 	mov    rdx,QWORD PTR [rsp+0x1d0]
     f9e:	00 
     f9f:	89 84 24 b8 03 00 00 	mov    DWORD PTR [rsp+0x3b8],eax
     fa6:	48 89 94 24 f8 02 00 	mov    QWORD PTR [rsp+0x2f8],rdx
     fad:	00 
     fae:	8b 84 24 b8 03 00 00 	mov    eax,DWORD PTR [rsp+0x3b8]
     fb5:	e8 00 00 00 00       	call   fba <mem.findScalarPos__anon_195+0xe9a>
     fba:	66 89 84 24 c0 03 00 	mov    WORD PTR [rsp+0x3c0],ax
     fc1:	00 
     fc2:	8a 94 24 c0 03 00 00 	mov    dl,BYTE PTR [rsp+0x3c0]
     fc9:	0f b6 d2             	movzx  edx,dl
     fcc:	48 01 94 24 f8 02 00 	add    QWORD PTR [rsp+0x2f8],rdx
     fd3:	00 
     fd4:	48 8b 84 24 f8 02 00 	mov    rax,QWORD PTR [rsp+0x2f8]
     fdb:	00 
     fdc:	48 89 84 24 00 03 00 	mov    QWORD PTR [rsp+0x300],rax
     fe3:	00 
     fe4:	c6 84 24 08 03 00 00 	mov    BYTE PTR [rsp+0x308],0x1
     feb:	01 
     fec:	48 8b 84 24 a0 01 00 	mov    rax,QWORD PTR [rsp+0x1a0]
     ff3:	00 
     ff4:	c5 fa 6f 84 24 00 03 	vmovdqu xmm0,XMMWORD PTR [rsp+0x300]
     ffb:	00 00 
     ffd:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
    1001:	e9 50 04 00 00       	jmp    1456 <mem.findScalarPos__anon_195+0x1336>
    1006:	e9 00 00 00 00       	jmp    100b <mem.findScalarPos__anon_195+0xeeb>
    100b:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
    1012:	00 
    1013:	48 83 c0 20          	add    rax,0x20
    1017:	48 89 84 24 d0 01 00 	mov    QWORD PTR [rsp+0x1d0],rax
    101e:	00 
    101f:	e9 05 00 00 00       	jmp    1029 <mem.findScalarPos__anon_195+0xf09>
    1024:	e9 00 00 00 00       	jmp    1029 <mem.findScalarPos__anon_195+0xf09>
    1029:	90                   	nop
    102a:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
    1031:	00 
    1032:	48 83 c0 10          	add    rax,0x10
    1036:	48 8b 94 24 c8 01 00 	mov    rdx,QWORD PTR [rsp+0x1c8]
    103d:	00 
    103e:	48 39 d0             	cmp    rax,rdx
    1041:	0f 83 0d 03 00 00    	jae    1354 <mem.findScalarPos__anon_195+0x1234>
    1047:	c4 e2 79 78 84 24 cb 	vpbroadcastb xmm0,BYTE PTR [rsp+0x3cb]
    104e:	03 00 00 
    1051:	c5 fa 7f 84 24 60 01 	vmovdqu XMMWORD PTR [rsp+0x160],xmm0
    1058:	00 00 
    105a:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
    1061:	00 
    1062:	c5 fa 6f 8c 24 c0 01 	vmovdqu xmm1,XMMWORD PTR [rsp+0x1c0]
    1069:	00 00 
    106b:	c5 fa 7f 8c 24 10 03 	vmovdqu XMMWORD PTR [rsp+0x310],xmm1
    1072:	00 00 
    1074:	48 8b 94 24 10 03 00 	mov    rdx,QWORD PTR [rsp+0x310]
    107b:	00 
    107c:	48 8d 1c 02          	lea    rbx,[rdx+rax*1]
    1080:	c5 fa 6f 0b          	vmovdqu xmm1,XMMWORD PTR [rbx]
    1084:	c5 fa 7f 8c 24 20 03 	vmovdqu XMMWORD PTR [rsp+0x320],xmm1
    108b:	00 00 
    108d:	0f b6 84 24 20 03 00 	movzx  eax,BYTE PTR [rsp+0x320]
    1094:	00 
    1095:	0f b6 94 24 21 03 00 	movzx  edx,BYTE PTR [rsp+0x321]
    109c:	00 
    109d:	0f b6 9c 24 22 03 00 	movzx  ebx,BYTE PTR [rsp+0x322]
    10a4:	00 
    10a5:	0f b6 8c 24 23 03 00 	movzx  ecx,BYTE PTR [rsp+0x323]
    10ac:	00 
    10ad:	0f b6 b4 24 24 03 00 	movzx  esi,BYTE PTR [rsp+0x324]
    10b4:	00 
    10b5:	0f b6 bc 24 25 03 00 	movzx  edi,BYTE PTR [rsp+0x325]
    10bc:	00 
    10bd:	44 0f b6 84 24 26 03 	movzx  r8d,BYTE PTR [rsp+0x326]
    10c4:	00 00 
    10c6:	44 0f b6 8c 24 27 03 	movzx  r9d,BYTE PTR [rsp+0x327]
    10cd:	00 00 
    10cf:	44 0f b6 94 24 28 03 	movzx  r10d,BYTE PTR [rsp+0x328]
    10d6:	00 00 
    10d8:	44 0f b6 9c 24 29 03 	movzx  r11d,BYTE PTR [rsp+0x329]
    10df:	00 00 
    10e1:	44 0f b6 a4 24 2a 03 	movzx  r12d,BYTE PTR [rsp+0x32a]
    10e8:	00 00 
    10ea:	44 0f b6 ac 24 2b 03 	movzx  r13d,BYTE PTR [rsp+0x32b]
    10f1:	00 00 
    10f3:	44 0f b6 b4 24 2c 03 	movzx  r14d,BYTE PTR [rsp+0x32c]
    10fa:	00 00 
    10fc:	44 0f b6 bc 24 2d 03 	movzx  r15d,BYTE PTR [rsp+0x32d]
    1103:	00 00 
    1105:	88 84 24 11 04 00 00 	mov    BYTE PTR [rsp+0x411],al
    110c:	0f b6 84 24 2e 03 00 	movzx  eax,BYTE PTR [rsp+0x32e]
    1113:	00 
    1114:	88 84 24 12 04 00 00 	mov    BYTE PTR [rsp+0x412],al
    111b:	0f b6 84 24 2f 03 00 	movzx  eax,BYTE PTR [rsp+0x32f]
    1122:	00 
    1123:	88 84 24 13 04 00 00 	mov    BYTE PTR [rsp+0x413],al
    112a:	40 88 bc 24 14 04 00 	mov    BYTE PTR [rsp+0x414],dil
    1131:	00 
    1132:	88 94 24 15 04 00 00 	mov    BYTE PTR [rsp+0x415],dl
    1139:	48 8d 94 24 70 01 00 	lea    rdx,[rsp+0x170]
    1140:	00 
    1141:	48 89 94 24 30 03 00 	mov    QWORD PTR [rsp+0x330],rdx
    1148:	00 
    1149:	48 8b bc 24 30 03 00 	mov    rdi,QWORD PTR [rsp+0x330]
    1150:	00 
    1151:	40 88 b4 24 16 04 00 	mov    BYTE PTR [rsp+0x416],sil
    1158:	00 
    1159:	48 8d 94 24 11 04 00 	lea    rdx,[rsp+0x411]
    1160:	00 
    1161:	48 89 94 24 38 03 00 	mov    QWORD PTR [rsp+0x338],rdx
    1168:	00 
    1169:	48 8b b4 24 38 03 00 	mov    rsi,QWORD PTR [rsp+0x338]
    1170:	00 
    1171:	88 8c 24 17 04 00 00 	mov    BYTE PTR [rsp+0x417],cl
    1178:	48 89 84 24 40 03 00 	mov    QWORD PTR [rsp+0x340],rax
    117f:	00 
    1180:	48 8b 8c 24 40 03 00 	mov    rcx,QWORD PTR [rsp+0x340]
    1187:	00 
    1188:	48 c7 c1 01 00 00 00 	mov    rcx,0x1
    118f:	f3 a4                	rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
    1191:	8a 84 24 15 04 00 00 	mov    al,BYTE PTR [rsp+0x415]
    1198:	88 84 24 71 01 00 00 	mov    BYTE PTR [rsp+0x171],al
    119f:	88 9c 24 72 01 00 00 	mov    BYTE PTR [rsp+0x172],bl
    11a6:	8a 84 24 17 04 00 00 	mov    al,BYTE PTR [rsp+0x417]
    11ad:	88 84 24 73 01 00 00 	mov    BYTE PTR [rsp+0x173],al
    11b4:	8a 84 24 16 04 00 00 	mov    al,BYTE PTR [rsp+0x416]
    11bb:	88 84 24 74 01 00 00 	mov    BYTE PTR [rsp+0x174],al
    11c2:	8a 84 24 14 04 00 00 	mov    al,BYTE PTR [rsp+0x414]
    11c9:	88 84 24 75 01 00 00 	mov    BYTE PTR [rsp+0x175],al
    11d0:	44 88 84 24 76 01 00 	mov    BYTE PTR [rsp+0x176],r8b
    11d7:	00 
    11d8:	44 88 8c 24 77 01 00 	mov    BYTE PTR [rsp+0x177],r9b
    11df:	00 
    11e0:	44 88 94 24 78 01 00 	mov    BYTE PTR [rsp+0x178],r10b
    11e7:	00 
    11e8:	44 88 9c 24 79 01 00 	mov    BYTE PTR [rsp+0x179],r11b
    11ef:	00 
    11f0:	44 88 a4 24 7a 01 00 	mov    BYTE PTR [rsp+0x17a],r12b
    11f7:	00 
    11f8:	44 88 ac 24 7b 01 00 	mov    BYTE PTR [rsp+0x17b],r13b
    11ff:	00 
    1200:	44 88 b4 24 7c 01 00 	mov    BYTE PTR [rsp+0x17c],r14b
    1207:	00 
    1208:	44 88 bc 24 7d 01 00 	mov    BYTE PTR [rsp+0x17d],r15b
    120f:	00 
    1210:	8a 84 24 12 04 00 00 	mov    al,BYTE PTR [rsp+0x412]
    1217:	88 84 24 7e 01 00 00 	mov    BYTE PTR [rsp+0x17e],al
    121e:	8a 84 24 13 04 00 00 	mov    al,BYTE PTR [rsp+0x413]
    1225:	88 84 24 7f 01 00 00 	mov    BYTE PTR [rsp+0x17f],al
    122c:	c5 fa 6f 8c 24 70 01 	vmovdqu xmm1,XMMWORD PTR [rsp+0x170]
    1233:	00 00 
    1235:	c5 fa 7f 8c 24 80 01 	vmovdqu XMMWORD PTR [rsp+0x180],xmm1
    123c:	00 00 
    123e:	48 c7 84 24 48 03 00 	mov    QWORD PTR [rsp+0x348],0x0
    1245:	00 00 00 00 00 
    124a:	48 8b 84 24 48 03 00 	mov    rax,QWORD PTR [rsp+0x348]
    1251:	00 
    1252:	0f b6 94 04 70 01 00 	movzx  edx,BYTE PTR [rsp+rax*1+0x170]
    1259:	00 
    125a:	c5 fa 7f 84 24 90 01 	vmovdqu XMMWORD PTR [rsp+0x190],xmm0
    1261:	00 00 
    1263:	0f b6 9c 04 90 01 00 	movzx  ebx,BYTE PTR [rsp+rax*1+0x190]
    126a:	00 
    126b:	38 da                	cmp    dl,bl
    126d:	48 8d 94 24 c2 03 00 	lea    rdx,[rsp+0x3c2]
    1274:	00 
    1275:	0f 94 c3             	sete   bl
    1278:	0f b7 0a             	movzx  ecx,WORD PTR [rdx]
    127b:	89 ce                	mov    esi,ecx
    127d:	0f b3 c6             	btr    esi,eax
    1280:	0f ab c1             	bts    ecx,eax
    1283:	f6 c3 01             	test   bl,0x1
    1286:	0f 44 ce             	cmove  ecx,esi
    1289:	66 89 0a             	mov    WORD PTR [rdx],cx
    128c:	48 83 f8 0f          	cmp    rax,0xf
    1290:	0f 85 0d 00 00 00    	jne    12a3 <mem.findScalarPos__anon_195+0x1183>
    1296:	66 8b 84 24 c2 03 00 	mov    ax,WORD PTR [rsp+0x3c2]
    129d:	00 
    129e:	e9 11 00 00 00       	jmp    12b4 <mem.findScalarPos__anon_195+0x1194>
    12a3:	48 83 c0 01          	add    rax,0x1
    12a7:	48 89 84 24 48 03 00 	mov    QWORD PTR [rsp+0x348],rax
    12ae:	00 
    12af:	e9 96 ff ff ff       	jmp    124a <mem.findScalarPos__anon_195+0x112a>
    12b4:	66 89 84 24 c4 03 00 	mov    WORD PTR [rsp+0x3c4],ax
    12bb:	00 
    12bc:	66 85 c0             	test   ax,ax
    12bf:	0f 84 71 00 00 00    	je     1336 <mem.findScalarPos__anon_195+0x1216>
    12c5:	48 8b 94 24 d0 01 00 	mov    rdx,QWORD PTR [rsp+0x1d0]
    12cc:	00 
    12cd:	66 89 84 24 c6 03 00 	mov    WORD PTR [rsp+0x3c6],ax
    12d4:	00 
    12d5:	48 89 94 24 50 03 00 	mov    QWORD PTR [rsp+0x350],rdx
    12dc:	00 
    12dd:	66 8b 84 24 c6 03 00 	mov    ax,WORD PTR [rsp+0x3c6]
    12e4:	00 
    12e5:	e8 00 00 00 00       	call   12ea <mem.findScalarPos__anon_195+0x11ca>
    12ea:	66 89 84 24 c8 03 00 	mov    WORD PTR [rsp+0x3c8],ax
    12f1:	00 
    12f2:	8a 94 24 c8 03 00 00 	mov    dl,BYTE PTR [rsp+0x3c8]
    12f9:	0f b6 d2             	movzx  edx,dl
    12fc:	48 01 94 24 50 03 00 	add    QWORD PTR [rsp+0x350],rdx
    1303:	00 
    1304:	48 8b 84 24 50 03 00 	mov    rax,QWORD PTR [rsp+0x350]
    130b:	00 
    130c:	48 89 84 24 58 03 00 	mov    QWORD PTR [rsp+0x358],rax
    1313:	00 
    1314:	c6 84 24 60 03 00 00 	mov    BYTE PTR [rsp+0x360],0x1
    131b:	01 
    131c:	48 8b 84 24 a0 01 00 	mov    rax,QWORD PTR [rsp+0x1a0]
    1323:	00 
    1324:	c5 fa 6f 84 24 58 03 	vmovdqu xmm0,XMMWORD PTR [rsp+0x358]
    132b:	00 00 
    132d:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
    1331:	e9 20 01 00 00       	jmp    1456 <mem.findScalarPos__anon_195+0x1336>
    1336:	e9 00 00 00 00       	jmp    133b <mem.findScalarPos__anon_195+0x121b>
    133b:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
    1342:	00 
    1343:	48 83 c0 10          	add    rax,0x10
    1347:	48 89 84 24 d0 01 00 	mov    QWORD PTR [rsp+0x1d0],rax
    134e:	00 
    134f:	e9 05 00 00 00       	jmp    1359 <mem.findScalarPos__anon_195+0x1239>
    1354:	e9 00 00 00 00       	jmp    1359 <mem.findScalarPos__anon_195+0x1239>
    1359:	90                   	nop
    135a:	e9 05 00 00 00       	jmp    1364 <mem.findScalarPos__anon_195+0x1244>
    135f:	e9 00 00 00 00       	jmp    1364 <mem.findScalarPos__anon_195+0x1244>
    1364:	48 c7 84 24 68 03 00 	mov    QWORD PTR [rsp+0x368],0x0
    136b:	00 00 00 00 00 
    1370:	48 8b 84 24 d0 01 00 	mov    rax,QWORD PTR [rsp+0x1d0]
    1377:	00 
    1378:	c5 fa 6f 84 24 c0 01 	vmovdqu xmm0,XMMWORD PTR [rsp+0x1c0]
    137f:	00 00 
    1381:	c5 fa 7f 84 24 70 03 	vmovdqu XMMWORD PTR [rsp+0x370],xmm0
    1388:	00 00 
    138a:	48 8b 94 24 70 03 00 	mov    rdx,QWORD PTR [rsp+0x370]
    1391:	00 
    1392:	48 8d 1c 02          	lea    rbx,[rdx+rax*1]
    1396:	48 29 84 24 78 03 00 	sub    QWORD PTR [rsp+0x378],rax
    139d:	00 
    139e:	48 8b 84 24 78 03 00 	mov    rax,QWORD PTR [rsp+0x378]
    13a5:	00 
    13a6:	48 8b 94 24 d0 01 00 	mov    rdx,QWORD PTR [rsp+0x1d0]
    13ad:	00 
    13ae:	48 89 c1             	mov    rcx,rax
    13b1:	48 8b b4 24 68 03 00 	mov    rsi,QWORD PTR [rsp+0x368]
    13b8:	00 
    13b9:	48 89 f7             	mov    rdi,rsi
    13bc:	49 89 c8             	mov    r8,rcx
    13bf:	4c 39 c7             	cmp    rdi,r8
    13c2:	0f 83 61 00 00 00    	jae    1429 <mem.findScalarPos__anon_195+0x1309>
    13c8:	48 89 df             	mov    rdi,rbx
    13cb:	44 0f b6 04 37       	movzx  r8d,BYTE PTR [rdi+rsi*1]
    13d0:	44 88 84 24 18 04 00 	mov    BYTE PTR [rsp+0x418],r8b
    13d7:	00 
    13d8:	48 89 d7             	mov    rdi,rdx
    13db:	48 01 f7             	add    rdi,rsi
    13de:	48 89 bc 24 80 03 00 	mov    QWORD PTR [rsp+0x380],rdi
    13e5:	00 
    13e6:	44 3a 84 24 cb 03 00 	cmp    r8b,BYTE PTR [rsp+0x3cb]
    13ed:	00 
    13ee:	0f 85 2a 00 00 00    	jne    141e <mem.findScalarPos__anon_195+0x12fe>
    13f4:	48 89 bc 24 88 03 00 	mov    QWORD PTR [rsp+0x388],rdi
    13fb:	00 
    13fc:	c6 84 24 90 03 00 00 	mov    BYTE PTR [rsp+0x390],0x1
    1403:	01 
    1404:	48 8b 84 24 a0 01 00 	mov    rax,QWORD PTR [rsp+0x1a0]
    140b:	00 
    140c:	c5 fa 6f 84 24 88 03 	vmovdqu xmm0,XMMWORD PTR [rsp+0x388]
    1413:	00 00 
    1415:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
    1419:	e9 38 00 00 00       	jmp    1456 <mem.findScalarPos__anon_195+0x1336>
    141e:	e9 00 00 00 00       	jmp    1423 <mem.findScalarPos__anon_195+0x1303>
    1423:	90                   	nop
    1424:	e9 05 00 00 00       	jmp    142e <mem.findScalarPos__anon_195+0x130e>
    1429:	e9 11 00 00 00       	jmp    143f <mem.findScalarPos__anon_195+0x131f>
    142e:	48 83 c6 01          	add    rsi,0x1
    1432:	48 89 b4 24 68 03 00 	mov    QWORD PTR [rsp+0x368],rsi
    1439:	00 
    143a:	e9 72 ff ff ff       	jmp    13b1 <mem.findScalarPos__anon_195+0x1291>
    143f:	48 8b 84 24 a0 01 00 	mov    rax,QWORD PTR [rsp+0x1a0]
    1446:	00 
    1447:	48 c7 c2 00 00 00 00 	mov    rdx,0x0
    144e:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
    1452:	c5 fa 7f 00          	vmovdqu XMMWORD PTR [rax],xmm0
    1456:	48 8d 65 d8          	lea    rsp,[rbp-0x28]
    145a:	41 5b                	pop    r11
    145c:	41 5c                	pop    r12
    145e:	41 5d                	pop    r13
    1460:	41 5e                	pop    r14
    1462:	41 5f                	pop    r15
    1464:	5d                   	pop    rbp
    1465:	c3                   	ret
	...

0000000000001ae0 <math.isPowerOfTwo__anon_559>:
    1ae0:	55                   	push   rbp
    1ae1:	48 89 e5             	mov    rbp,rsp
    1ae4:	48 83 ec 10          	sub    rsp,0x10
    1ae8:	b0 01                	mov    al,0x1
    1aea:	e8 00 00 00 00       	call   1aef <math.isPowerOfTwo__anon_559+0xf>
    1aef:	b0 01                	mov    al,0x1
    1af1:	48 89 ec             	mov    rsp,rbp
    1af4:	5d                   	pop    rbp
    1af5:	c3                   	ret
	...

0000000000001b00 <simd.firstTrue__anon_1490>:
    1b00:	55                   	push   rbp
    1b01:	48 89 e5             	mov    rbp,rsp
    1b04:	48 83 ec 40          	sub    rsp,0x40
    1b08:	66 89 44 24 38       	mov    WORD PTR [rsp+0x38],ax
    1b0d:	66 85 c0             	test   ax,ax
    1b10:	0f 95 c2             	setne  dl
    1b13:	80 f2 01             	xor    dl,0x1
    1b16:	f6 c2 01             	test   dl,0x1
    1b19:	0f 84 0d 00 00 00    	je     1b2c <simd.firstTrue__anon_1490+0x2c>
    1b1f:	66 8b 04 25 00 00 00 	mov    ax,WORD PTR ds:0x0
    1b26:	00 
    1b27:	e9 c0 00 00 00       	jmp    1bec <simd.firstTrue__anon_1490+0xec>
    1b2c:	e9 00 00 00 00       	jmp    1b31 <simd.firstTrue__anon_1490+0x31>
    1b31:	48 c7 c2 00 00 00 00 	mov    rdx,0x0
    1b38:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
    1b3c:	c5 fa 7f 04 24       	vmovdqu XMMWORD PTR [rsp],xmm0
    1b41:	48 c7 44 24 30 00 00 	mov    QWORD PTR [rsp+0x30],0x0
    1b48:	00 00 
    1b4a:	48 8b 54 24 30       	mov    rdx,QWORD PTR [rsp+0x30]
    1b4f:	0f a3 d0             	bt     eax,edx
    1b52:	0f 83 10 00 00 00    	jae    1b68 <simd.firstTrue__anon_1490+0x68>
    1b58:	48 c7 c3 00 00 00 00 	mov    rbx,0x0
    1b5f:	0f b6 0c 13          	movzx  ecx,BYTE PTR [rbx+rdx*1]
    1b63:	e9 18 00 00 00       	jmp    1b80 <simd.firstTrue__anon_1490+0x80>
    1b68:	48 c7 c3 00 00 00 00 	mov    rbx,0x0
    1b6f:	0f b6 0c 13          	movzx  ecx,BYTE PTR [rbx+rdx*1]
    1b73:	88 4c 24 3c          	mov    BYTE PTR [rsp+0x3c],cl
    1b77:	8a 4c 24 3c          	mov    cl,BYTE PTR [rsp+0x3c]
    1b7b:	e9 00 00 00 00       	jmp    1b80 <simd.firstTrue__anon_1490+0x80>
    1b80:	48 8d 5c 24 10       	lea    rbx,[rsp+0x10]
    1b85:	88 0c 13             	mov    BYTE PTR [rbx+rdx*1],cl
    1b88:	48 83 fa 0f          	cmp    rdx,0xf
    1b8c:	0f 85 0b 00 00 00    	jne    1b9d <simd.firstTrue__anon_1490+0x9d>
    1b92:	c5 fa 6f 44 24 10    	vmovdqu xmm0,XMMWORD PTR [rsp+0x10]
    1b98:	e9 0e 00 00 00       	jmp    1bab <simd.firstTrue__anon_1490+0xab>
    1b9d:	48 83 c2 01          	add    rdx,0x1
    1ba1:	48 89 54 24 30       	mov    QWORD PTR [rsp+0x30],rdx
    1ba6:	e9 9f ff ff ff       	jmp    1b4a <simd.firstTrue__anon_1490+0x4a>
    1bab:	c5 fa 7f 44 24 20    	vmovdqu XMMWORD PTR [rsp+0x20],xmm0
    1bb1:	c5 f9 70 c8 0e       	vpshufd xmm1,xmm0,0xe
    1bb6:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1bba:	c5 fb 70 c8 0e       	vpshuflw xmm1,xmm0,0xe
    1bbf:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1bc3:	c5 fb 70 c8 01       	vpshuflw xmm1,xmm0,0x1
    1bc8:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1bcc:	c5 f1 71 d0 08       	vpsrlw xmm1,xmm0,0x8
    1bd1:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1bd5:	66 89 44 24 3a       	mov    WORD PTR [rsp+0x3a],ax
    1bda:	c4 e3 79 14 44 24 3a 	vpextrb BYTE PTR [rsp+0x3a],xmm0,0x0
    1be1:	00 
    1be2:	c6 44 24 3b 01       	mov    BYTE PTR [rsp+0x3b],0x1
    1be7:	66 8b 44 24 3a       	mov    ax,WORD PTR [rsp+0x3a]
    1bec:	48 89 ec             	mov    rsp,rbp
    1bef:	5d                   	pop    rbp
    1bf0:	c3                   	ret
	...

0000000000001c50 <debug.assert>:
    1c50:	55                   	push   rbp
    1c51:	48 89 e5             	mov    rbp,rsp
    1c54:	48 83 ec 01          	sub    rsp,0x1
    1c58:	88 04 24             	mov    BYTE PTR [rsp],al
    1c5b:	34 01                	xor    al,0x1
    1c5d:	a8 01                	test   al,0x1
    1c5f:	0f 84 00 00 00 00    	je     1c65 <debug.assert+0x15>
    1c65:	e9 00 00 00 00       	jmp    1c6a <debug.assert+0x1a>
    1c6a:	48 89 ec             	mov    rsp,rbp
    1c6d:	5d                   	pop    rbp
    1c6e:	c3                   	ret
	...

0000000000001c80 <simd.firstTrue__anon_1470>:
    1c80:	55                   	push   rbp
    1c81:	48 89 e5             	mov    rbp,rsp
    1c84:	48 83 ec 70          	sub    rsp,0x70
    1c88:	89 44 24 68          	mov    DWORD PTR [rsp+0x68],eax
    1c8c:	85 c0                	test   eax,eax
    1c8e:	0f 95 c2             	setne  dl
    1c91:	80 f2 01             	xor    dl,0x1
    1c94:	f6 c2 01             	test   dl,0x1
    1c97:	0f 84 0d 00 00 00    	je     1caa <simd.firstTrue__anon_1470+0x2a>
    1c9d:	66 8b 04 25 00 00 00 	mov    ax,WORD PTR ds:0x0
    1ca4:	00 
    1ca5:	e9 ca 00 00 00       	jmp    1d74 <simd.firstTrue__anon_1470+0xf4>
    1caa:	e9 00 00 00 00       	jmp    1caf <simd.firstTrue__anon_1470+0x2f>
    1caf:	48 c7 c2 00 00 00 00 	mov    rdx,0x0
    1cb6:	c5 fe 6f 02          	vmovdqu ymm0,YMMWORD PTR [rdx]
    1cba:	c5 fe 7f 04 24       	vmovdqu YMMWORD PTR [rsp],ymm0
    1cbf:	48 c7 44 24 60 00 00 	mov    QWORD PTR [rsp+0x60],0x0
    1cc6:	00 00 
    1cc8:	48 8b 54 24 60       	mov    rdx,QWORD PTR [rsp+0x60]
    1ccd:	0f a3 d0             	bt     eax,edx
    1cd0:	0f 83 10 00 00 00    	jae    1ce6 <simd.firstTrue__anon_1470+0x66>
    1cd6:	48 c7 c3 00 00 00 00 	mov    rbx,0x0
    1cdd:	0f b6 0c 13          	movzx  ecx,BYTE PTR [rbx+rdx*1]
    1ce1:	e9 18 00 00 00       	jmp    1cfe <simd.firstTrue__anon_1470+0x7e>
    1ce6:	48 c7 c3 00 00 00 00 	mov    rbx,0x0
    1ced:	0f b6 0c 13          	movzx  ecx,BYTE PTR [rbx+rdx*1]
    1cf1:	88 4c 24 6e          	mov    BYTE PTR [rsp+0x6e],cl
    1cf5:	8a 4c 24 6e          	mov    cl,BYTE PTR [rsp+0x6e]
    1cf9:	e9 00 00 00 00       	jmp    1cfe <simd.firstTrue__anon_1470+0x7e>
    1cfe:	48 8d 5c 24 20       	lea    rbx,[rsp+0x20]
    1d03:	88 0c 13             	mov    BYTE PTR [rbx+rdx*1],cl
    1d06:	48 83 fa 1f          	cmp    rdx,0x1f
    1d0a:	0f 85 0b 00 00 00    	jne    1d1b <simd.firstTrue__anon_1470+0x9b>
    1d10:	c5 fe 6f 44 24 20    	vmovdqu ymm0,YMMWORD PTR [rsp+0x20]
    1d16:	e9 0e 00 00 00       	jmp    1d29 <simd.firstTrue__anon_1470+0xa9>
    1d1b:	48 83 c2 01          	add    rdx,0x1
    1d1f:	48 89 54 24 60       	mov    QWORD PTR [rsp+0x60],rdx
    1d24:	e9 9f ff ff ff       	jmp    1cc8 <simd.firstTrue__anon_1470+0x48>
    1d29:	c5 fe 7f 44 24 40    	vmovdqu YMMWORD PTR [rsp+0x40],ymm0
    1d2f:	c4 e3 7d 39 c1 01    	vextracti128 xmm1,ymm0,0x1
    1d35:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1d39:	c5 f9 70 c8 0e       	vpshufd xmm1,xmm0,0xe
    1d3e:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1d42:	c5 fb 70 c8 0e       	vpshuflw xmm1,xmm0,0xe
    1d47:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1d4b:	c5 fb 70 c8 01       	vpshuflw xmm1,xmm0,0x1
    1d50:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1d54:	c5 f1 71 d0 08       	vpsrlw xmm1,xmm0,0x8
    1d59:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
    1d5d:	66 89 44 24 6c       	mov    WORD PTR [rsp+0x6c],ax
    1d62:	c4 e3 79 14 44 24 6c 	vpextrb BYTE PTR [rsp+0x6c],xmm0,0x0
    1d69:	00 
    1d6a:	c6 44 24 6d 01       	mov    BYTE PTR [rsp+0x6d],0x1
    1d6f:	66 8b 44 24 6c       	mov    ax,WORD PTR [rsp+0x6c]
    1d74:	48 89 ec             	mov    rsp,rbp
    1d77:	5d                   	pop    rbp
    1d78:	c3                   	ret
	...

0000000000001dd0 <is_ascii>:
    1dd0:	55                   	push   rbp
    1dd1:	48 89 e5             	mov    rbp,rsp
    1dd4:	53                   	push   rbx
    1dd5:	48 83 e4 e0          	and    rsp,0xffffffffffffffe0
    1dd9:	48 81 ec 00 01 00 00 	sub    rsp,0x100
    1de0:	48 89 7c 24 60       	mov    QWORD PTR [rsp+0x60],rdi
    1de5:	48 89 74 24 68       	mov    QWORD PTR [rsp+0x68],rsi
    1dea:	48 89 7c 24 70       	mov    QWORD PTR [rsp+0x70],rdi
    1def:	48 8b 44 24 70       	mov    rax,QWORD PTR [rsp+0x70]
    1df4:	48 8d 10             	lea    rdx,[rax]
    1df7:	48 83 ee 00          	sub    rsi,0x0
    1dfb:	48 89 54 24 78       	mov    QWORD PTR [rsp+0x78],rdx
    1e00:	48 89 b4 24 80 00 00 	mov    QWORD PTR [rsp+0x80],rsi
    1e07:	00 
    1e08:	48 89 94 24 88 00 00 	mov    QWORD PTR [rsp+0x88],rdx
    1e0f:	00 
    1e10:	48 89 b4 24 90 00 00 	mov    QWORD PTR [rsp+0x90],rsi
    1e17:	00 
    1e18:	48 c7 c0 00 00 00 00 	mov    rax,0x0
    1e1f:	c5 fe 6f 00          	vmovdqu ymm0,YMMWORD PTR [rax]
    1e23:	c5 fe 7f 04 24       	vmovdqu YMMWORD PTR [rsp],ymm0
    1e28:	48 c7 c0 00 00 00 00 	mov    rax,0x0
    1e2f:	c5 fe 6f 00          	vmovdqu ymm0,YMMWORD PTR [rax]
    1e33:	c5 fe 7f 44 24 20    	vmovdqu YMMWORD PTR [rsp+0x20],ymm0
    1e39:	48 c7 84 24 98 00 00 	mov    QWORD PTR [rsp+0x98],0x0
    1e40:	00 00 00 00 00 
    1e45:	48 8b 84 24 98 00 00 	mov    rax,QWORD PTR [rsp+0x98]
    1e4c:	00 
    1e4d:	48 83 c0 20          	add    rax,0x20
    1e51:	48 8b 94 24 80 00 00 	mov    rdx,QWORD PTR [rsp+0x80]
    1e58:	00 
    1e59:	48 39 c2             	cmp    rdx,rax
    1e5c:	0f 82 00 01 00 00    	jb     1f62 <is_ascii+0x192>
    1e62:	48 8b 84 24 98 00 00 	mov    rax,QWORD PTR [rsp+0x98]
    1e69:	00 
    1e6a:	c5 fa 6f 44 24 78    	vmovdqu xmm0,XMMWORD PTR [rsp+0x78]
    1e70:	c5 fa 7f 84 24 a0 00 	vmovdqu XMMWORD PTR [rsp+0xa0],xmm0
    1e77:	00 00 
    1e79:	48 8b 94 24 a0 00 00 	mov    rdx,QWORD PTR [rsp+0xa0]
    1e80:	00 
    1e81:	48 8d 1c 02          	lea    rbx,[rdx+rax*1]
    1e85:	48 29 84 24 a8 00 00 	sub    QWORD PTR [rsp+0xa8],rax
    1e8c:	00 
    1e8d:	48 8b 84 24 a8 00 00 	mov    rax,QWORD PTR [rsp+0xa8]
    1e94:	00 
    1e95:	48 89 9c 24 b0 00 00 	mov    QWORD PTR [rsp+0xb0],rbx
    1e9c:	00 
    1e9d:	48 89 84 24 b8 00 00 	mov    QWORD PTR [rsp+0xb8],rax
    1ea4:	00 
    1ea5:	48 8b 84 24 b0 00 00 	mov    rax,QWORD PTR [rsp+0xb0]
    1eac:	00 
    1ead:	48 89 84 24 c0 00 00 	mov    QWORD PTR [rsp+0xc0],rax
    1eb4:	00 
    1eb5:	c5 fe 6f 00          	vmovdqu ymm0,YMMWORD PTR [rax]
    1eb9:	48 c7 c0 00 00 00 00 	mov    rax,0x0
    1ec0:	c5 fd db 08          	vpand  ymm1,ymm0,YMMWORD PTR [rax]
    1ec4:	48 c7 84 24 c8 00 00 	mov    QWORD PTR [rsp+0xc8],0x0
    1ecb:	00 00 00 00 00 
    1ed0:	48 8b 84 24 c8 00 00 	mov    rax,QWORD PTR [rsp+0xc8]
    1ed7:	00 
    1ed8:	c5 fe 7f 4c 24 40    	vmovdqu YMMWORD PTR [rsp+0x40],ymm1
    1ede:	0f b6 54 04 40       	movzx  edx,BYTE PTR [rsp+rax*1+0x40]
    1ee3:	48 c7 c3 00 00 00 00 	mov    rbx,0x0
    1eea:	0f b6 0c 03          	movzx  ecx,BYTE PTR [rbx+rax*1]
    1eee:	38 ca                	cmp    dl,cl
    1ef0:	48 8d 94 24 e8 00 00 	lea    rdx,[rsp+0xe8]
    1ef7:	00 
    1ef8:	0f 95 c3             	setne  bl
    1efb:	8b 0a                	mov    ecx,DWORD PTR [rdx]
    1efd:	89 ce                	mov    esi,ecx
    1eff:	0f b3 c6             	btr    esi,eax
    1f02:	0f ab c1             	bts    ecx,eax
    1f05:	f6 c3 01             	test   bl,0x1
    1f08:	0f 44 ce             	cmove  ecx,esi
    1f0b:	89 0a                	mov    DWORD PTR [rdx],ecx
    1f0d:	48 83 f8 1f          	cmp    rax,0x1f
    1f11:	0f 85 0c 00 00 00    	jne    1f23 <is_ascii+0x153>
    1f17:	8b 84 24 e8 00 00 00 	mov    eax,DWORD PTR [rsp+0xe8]
    1f1e:	e9 11 00 00 00       	jmp    1f34 <is_ascii+0x164>
    1f23:	48 83 c0 01          	add    rax,0x1
    1f27:	48 89 84 24 c8 00 00 	mov    QWORD PTR [rsp+0xc8],rax
    1f2e:	00 
    1f2f:	e9 9c ff ff ff       	jmp    1ed0 <is_ascii+0x100>
    1f34:	85 c0                	test   eax,eax
    1f36:	0f 84 07 00 00 00    	je     1f43 <is_ascii+0x173>
    1f3c:	31 c0                	xor    eax,eax
    1f3e:	e9 c9 00 00 00       	jmp    200c <is_ascii+0x23c>
    1f43:	e9 00 00 00 00       	jmp    1f48 <is_ascii+0x178>
    1f48:	90                   	nop
    1f49:	48 8b 84 24 98 00 00 	mov    rax,QWORD PTR [rsp+0x98]
    1f50:	00 
    1f51:	48 83 c0 20          	add    rax,0x20
    1f55:	48 89 84 24 98 00 00 	mov    QWORD PTR [rsp+0x98],rax
    1f5c:	00 
    1f5d:	e9 05 00 00 00       	jmp    1f67 <is_ascii+0x197>
    1f62:	e9 05 00 00 00       	jmp    1f6c <is_ascii+0x19c>
    1f67:	e9 d9 fe ff ff       	jmp    1e45 <is_ascii+0x75>
    1f6c:	48 c7 84 24 d0 00 00 	mov    QWORD PTR [rsp+0xd0],0x0
    1f73:	00 00 00 00 00 
    1f78:	48 8b 84 24 98 00 00 	mov    rax,QWORD PTR [rsp+0x98]
    1f7f:	00 
    1f80:	c5 fa 6f 44 24 78    	vmovdqu xmm0,XMMWORD PTR [rsp+0x78]
    1f86:	c5 fa 7f 84 24 d8 00 	vmovdqu XMMWORD PTR [rsp+0xd8],xmm0
    1f8d:	00 00 
    1f8f:	48 8b 94 24 d8 00 00 	mov    rdx,QWORD PTR [rsp+0xd8]
    1f96:	00 
    1f97:	48 8d 1c 02          	lea    rbx,[rdx+rax*1]
    1f9b:	48 29 84 24 e0 00 00 	sub    QWORD PTR [rsp+0xe0],rax
    1fa2:	00 
    1fa3:	48 8b 84 24 e0 00 00 	mov    rax,QWORD PTR [rsp+0xe0]
    1faa:	00 
    1fab:	48 89 c2             	mov    rdx,rax
    1fae:	48 8b 8c 24 d0 00 00 	mov    rcx,QWORD PTR [rsp+0xd0]
    1fb5:	00 
    1fb6:	48 89 ce             	mov    rsi,rcx
    1fb9:	48 89 d7             	mov    rdi,rdx
    1fbc:	48 39 fe             	cmp    rsi,rdi
    1fbf:	0f 83 2f 00 00 00    	jae    1ff4 <is_ascii+0x224>
    1fc5:	48 89 de             	mov    rsi,rbx
    1fc8:	0f b6 3c 0e          	movzx  edi,BYTE PTR [rsi+rcx*1]
    1fcc:	40 88 bc 24 ec 00 00 	mov    BYTE PTR [rsp+0xec],dil
    1fd3:	00 
    1fd4:	40 80 e7 80          	and    dil,0x80
    1fd8:	40 80 ff 00          	cmp    dil,0x0
    1fdc:	0f 84 07 00 00 00    	je     1fe9 <is_ascii+0x219>
    1fe2:	31 c0                	xor    eax,eax
    1fe4:	e9 23 00 00 00       	jmp    200c <is_ascii+0x23c>
    1fe9:	e9 00 00 00 00       	jmp    1fee <is_ascii+0x21e>
    1fee:	90                   	nop
    1fef:	e9 05 00 00 00       	jmp    1ff9 <is_ascii+0x229>
    1ff4:	e9 11 00 00 00       	jmp    200a <is_ascii+0x23a>
    1ff9:	48 83 c1 01          	add    rcx,0x1
    1ffd:	48 89 8c 24 d0 00 00 	mov    QWORD PTR [rsp+0xd0],rcx
    2004:	00 
    2005:	e9 a4 ff ff ff       	jmp    1fae <is_ascii+0x1de>
    200a:	b0 01                	mov    al,0x1
    200c:	48 8d 65 f8          	lea    rsp,[rbp-0x8]
    2010:	5b                   	pop    rbx
    2011:	5d                   	pop    rbp
    2012:	c3                   	ret
