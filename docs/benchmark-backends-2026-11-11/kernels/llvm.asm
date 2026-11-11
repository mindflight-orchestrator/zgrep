
/tmp/zgrep-backends-20261111-3ahjbzi8/explain/llvm.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <first_zero>:
   0:	55                   	push   rbp
   1:	48 89 e5             	mov    rbp,rsp
   4:	48 89 f0             	mov    rax,rsi
   7:	48 85 f6             	test   rsi,rsi
   a:	0f 84 72 01 00 00    	je     182 <first_zero+0x182>
  10:	48 83 f8 41          	cmp    rax,0x41
  14:	0f 82 c7 00 00 00    	jb     e1 <first_zero+0xe1>
  1a:	31 c9                	xor    ecx,ecx
  1c:	c5 f9 ef c0          	vpxor  xmm0,xmm0,xmm0
  20:	c5 fe 6f 0c 0f       	vmovdqu ymm1,YMMWORD PTR [rdi+rcx*1]
  25:	c5 f5 74 d0          	vpcmpeqb ymm2,ymm1,ymm0
  29:	c5 fd d7 d2          	vpmovmskb edx,ymm2
  2d:	85 d2                	test   edx,edx
  2f:	0f 85 52 01 00 00    	jne    187 <first_zero+0x187>
  35:	c5 fe 6f 4c 0f 20    	vmovdqu ymm1,YMMWORD PTR [rdi+rcx*1+0x20]
  3b:	c5 f5 74 d0          	vpcmpeqb ymm2,ymm1,ymm0
  3f:	c5 fd d7 d2          	vpmovmskb edx,ymm2
  43:	85 d2                	test   edx,edx
  45:	0f 85 aa 01 00 00    	jne    1f5 <first_zero+0x1f5>
  4b:	48 8d 51 40          	lea    rdx,[rcx+0x40]
  4f:	48 83 e9 80          	sub    rcx,0xffffffffffffff80
  53:	48 39 c1             	cmp    rcx,rax
  56:	48 89 d1             	mov    rcx,rdx
  59:	72 c5                	jb     20 <first_zero+0x20>
  5b:	48 8d 4a 20          	lea    rcx,[rdx+0x20]
  5f:	48 39 c1             	cmp    rcx,rax
  62:	0f 83 88 00 00 00    	jae    f0 <first_zero+0xf0>
  68:	c5 f9 ef c0          	vpxor  xmm0,xmm0,xmm0
  6c:	c5 fd 74 04 17       	vpcmpeqb ymm0,ymm0,YMMWORD PTR [rdi+rdx*1]
  71:	c5 fd d7 f0          	vpmovmskb esi,ymm0
  75:	85 f6                	test   esi,esi
  77:	74 7a                	je     f3 <first_zero+0xf3>
  79:	c4 e2 7d 58 0d 00 00 	vpbroadcastd ymm1,DWORD PTR [rip+0x0]        # 82 <first_zero+0x82>
  80:	00 00 
  82:	c4 e3 75 4c 05 00 00 	vpblendvb ymm0,ymm1,YMMWORD PTR [rip+0x0],ymm0        # 8c <first_zero+0x8c>
  89:	00 00 00 
  8c:	c4 e3 7d 39 c2 01    	vextracti128 xmm2,ymm0,0x1
  92:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
  96:	c5 f9 70 d0 ee       	vpshufd xmm2,xmm0,0xee
  9b:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
  9f:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
  a3:	c5 f9 70 d0 55       	vpshufd xmm2,xmm0,0x55
  a8:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
  ac:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
  b0:	c5 e9 72 d0 10       	vpsrld xmm2,xmm0,0x10
  b5:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
  b9:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
  bd:	c5 e9 71 d0 08       	vpsrlw xmm2,xmm0,0x8
  c2:	c5 e9 db c9          	vpand  xmm1,xmm2,xmm1
  c6:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
  ca:	c5 f9 7e c0          	vmovd  eax,xmm0
  ce:	0f b7 c8             	movzx  ecx,ax
  d1:	24 1f                	and    al,0x1f
  d3:	88 45 fd             	mov    BYTE PTR [rbp-0x3],al
  d6:	48 01 ca             	add    rdx,rcx
  d9:	48 89 d0             	mov    rax,rdx
  dc:	5d                   	pop    rbp
  dd:	c5 f8 77             	vzeroupper
  e0:	c3                   	ret
  e1:	31 d2                	xor    edx,edx
  e3:	48 8d 4a 20          	lea    rcx,[rdx+0x20]
  e7:	48 39 c1             	cmp    rcx,rax
  ea:	0f 82 78 ff ff ff    	jb     68 <first_zero+0x68>
  f0:	48 89 d1             	mov    rcx,rdx
  f3:	48 8d 51 10          	lea    rdx,[rcx+0x10]
  f7:	48 39 c2             	cmp    rdx,rax
  fa:	73 69                	jae    165 <first_zero+0x165>
  fc:	c5 f9 ef c0          	vpxor  xmm0,xmm0,xmm0
 100:	c5 f9 74 04 0f       	vpcmpeqb xmm0,xmm0,XMMWORD PTR [rdi+rcx*1]
 105:	c5 f9 d7 f0          	vpmovmskb esi,xmm0
 109:	85 f6                	test   esi,esi
 10b:	74 70                	je     17d <first_zero+0x17d>
 10d:	c4 e2 79 58 0d 00 00 	vpbroadcastd xmm1,DWORD PTR [rip+0x0]        # 116 <first_zero+0x116>
 114:	00 00 
 116:	c4 e3 71 4c 05 00 00 	vpblendvb xmm0,xmm1,XMMWORD PTR [rip+0x0],xmm0        # 120 <first_zero+0x120>
 11d:	00 00 00 
 120:	c5 f9 70 d0 ee       	vpshufd xmm2,xmm0,0xee
 125:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 129:	c5 f9 70 d0 55       	vpshufd xmm2,xmm0,0x55
 12e:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 132:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 136:	c5 e9 72 d0 10       	vpsrld xmm2,xmm0,0x10
 13b:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 13f:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 143:	c5 e9 71 d0 08       	vpsrlw xmm2,xmm0,0x8
 148:	c5 e9 db c9          	vpand  xmm1,xmm2,xmm1
 14c:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
 150:	c5 f9 7e c0          	vmovd  eax,xmm0
 154:	88 45 fc             	mov    BYTE PTR [rbp-0x4],al
 157:	0f b7 c0             	movzx  eax,ax
 15a:	48 01 c1             	add    rcx,rax
 15d:	48 89 c8             	mov    rax,rcx
 160:	5d                   	pop    rbp
 161:	c5 f8 77             	vzeroupper
 164:	c3                   	ret
 165:	48 89 ca             	mov    rdx,rcx
 168:	eb 13                	jmp    17d <first_zero+0x17d>
 16a:	66 0f 1f 44 00 00    	nop    WORD PTR [rax+rax*1+0x0]
 170:	80 3c 17 00          	cmp    BYTE PTR [rdi+rdx*1],0x0
 174:	0f 84 ed 00 00 00    	je     267 <first_zero+0x267>
 17a:	48 ff c2             	inc    rdx
 17d:	48 39 d0             	cmp    rax,rdx
 180:	75 ee                	jne    170 <first_zero+0x170>
 182:	5d                   	pop    rbp
 183:	c5 f8 77             	vzeroupper
 186:	c3                   	ret
 187:	c5 f9 ef c0          	vpxor  xmm0,xmm0,xmm0
 18b:	c5 f5 74 c0          	vpcmpeqb ymm0,ymm1,ymm0
 18f:	c4 e2 7d 58 0d 00 00 	vpbroadcastd ymm1,DWORD PTR [rip+0x0]        # 198 <first_zero+0x198>
 196:	00 00 
 198:	c4 e3 75 4c 05 00 00 	vpblendvb ymm0,ymm1,YMMWORD PTR [rip+0x0],ymm0        # 1a2 <first_zero+0x1a2>
 19f:	00 00 00 
 1a2:	c4 e3 7d 39 c2 01    	vextracti128 xmm2,ymm0,0x1
 1a8:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 1ac:	c5 f9 70 d0 ee       	vpshufd xmm2,xmm0,0xee
 1b1:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 1b5:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 1b9:	c5 f9 70 d0 55       	vpshufd xmm2,xmm0,0x55
 1be:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 1c2:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 1c6:	c5 e9 72 d0 10       	vpsrld xmm2,xmm0,0x10
 1cb:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 1cf:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 1d3:	c5 e9 71 d0 08       	vpsrlw xmm2,xmm0,0x8
 1d8:	c5 e9 db c9          	vpand  xmm1,xmm2,xmm1
 1dc:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
 1e0:	c5 f9 7e c2          	vmovd  edx,xmm0
 1e4:	0f b7 c2             	movzx  eax,dx
 1e7:	80 e2 1f             	and    dl,0x1f
 1ea:	88 55 ff             	mov    BYTE PTR [rbp-0x1],dl
 1ed:	48 01 c8             	add    rax,rcx
 1f0:	5d                   	pop    rbp
 1f1:	c5 f8 77             	vzeroupper
 1f4:	c3                   	ret
 1f5:	c5 f9 ef c0          	vpxor  xmm0,xmm0,xmm0
 1f9:	c5 f5 74 c0          	vpcmpeqb ymm0,ymm1,ymm0
 1fd:	c4 e2 7d 58 0d 00 00 	vpbroadcastd ymm1,DWORD PTR [rip+0x0]        # 206 <first_zero+0x206>
 204:	00 00 
 206:	c4 e3 75 4c 05 00 00 	vpblendvb ymm0,ymm1,YMMWORD PTR [rip+0x0],ymm0        # 210 <first_zero+0x210>
 20d:	00 00 00 
 210:	c4 e3 7d 39 c2 01    	vextracti128 xmm2,ymm0,0x1
 216:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 21a:	c5 f9 70 d0 ee       	vpshufd xmm2,xmm0,0xee
 21f:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 223:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 227:	c5 f9 70 d0 55       	vpshufd xmm2,xmm0,0x55
 22c:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 230:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 234:	c5 e9 72 d0 10       	vpsrld xmm2,xmm0,0x10
 239:	c5 e9 db d1          	vpand  xmm2,xmm2,xmm1
 23d:	c5 f9 da c2          	vpminub xmm0,xmm0,xmm2
 241:	c5 e9 71 d0 08       	vpsrlw xmm2,xmm0,0x8
 246:	c5 e9 db c9          	vpand  xmm1,xmm2,xmm1
 24a:	c5 f9 da c1          	vpminub xmm0,xmm0,xmm1
 24e:	c5 f9 7e c0          	vmovd  eax,xmm0
 252:	0f b7 d0             	movzx  edx,ax
 255:	24 1f                	and    al,0x1f
 257:	88 45 fe             	mov    BYTE PTR [rbp-0x2],al
 25a:	48 8d 04 0a          	lea    rax,[rdx+rcx*1]
 25e:	48 83 c0 20          	add    rax,0x20
 262:	5d                   	pop    rbp
 263:	c5 f8 77             	vzeroupper
 266:	c3                   	ret
 267:	48 89 d0             	mov    rax,rdx
 26a:	5d                   	pop    rbp
 26b:	c5 f8 77             	vzeroupper
 26e:	c3                   	ret
 26f:	90                   	nop

0000000000000270 <is_ascii>:
 270:	31 c9                	xor    ecx,ecx
 272:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nop WORD PTR [rax+rax*1+0x0]
 279:	1f 84 00 00 00 00 00 
 280:	48 8d 41 20          	lea    rax,[rcx+0x20]
 284:	48 39 f0             	cmp    rax,rsi
 287:	77 16                	ja     29f <is_ascii+0x2f>
 289:	c5 fe 6f 04 0f       	vmovdqu ymm0,YMMWORD PTR [rdi+rcx*1]
 28e:	c5 fd d7 d0          	vpmovmskb edx,ymm0
 292:	48 89 c1             	mov    rcx,rax
 295:	85 d2                	test   edx,edx
 297:	74 e7                	je     280 <is_ascii+0x10>
 299:	31 c0                	xor    eax,eax
 29b:	c5 f8 77             	vzeroupper
 29e:	c3                   	ret
 29f:	b0 01                	mov    al,0x1
 2a1:	48 29 ce             	sub    rsi,rcx
 2a4:	75 04                	jne    2aa <is_ascii+0x3a>
 2a6:	c5 f8 77             	vzeroupper
 2a9:	c3                   	ret
 2aa:	55                   	push   rbp
 2ab:	48 89 e5             	mov    rbp,rsp
 2ae:	48 01 cf             	add    rdi,rcx
 2b1:	48 83 fe 01          	cmp    rsi,0x1
 2b5:	48 83 d6 ff          	adc    rsi,0xffffffffffffffff
 2b9:	0f 1f 80 00 00 00 00 	nop    DWORD PTR [rax+0x0]
 2c0:	48 83 c6 ff          	add    rsi,0xffffffffffffffff
 2c4:	0f 92 c1             	setb   cl
 2c7:	80 3f 00             	cmp    BYTE PTR [rdi],0x0
 2ca:	0f 99 c0             	setns  al
 2cd:	78 07                	js     2d6 <is_ascii+0x66>
 2cf:	48 ff c7             	inc    rdi
 2d2:	84 c9                	test   cl,cl
 2d4:	75 ea                	jne    2c0 <is_ascii+0x50>
 2d6:	5d                   	pop    rbp
 2d7:	c5 f8 77             	vzeroupper
 2da:	c3                   	ret
