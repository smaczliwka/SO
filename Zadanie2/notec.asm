
default rel

section .bss ; WAŻNE: rzeczy tutaj zainicjowane zerami
  align 8
  buff resq N + 1 ; wartość do wymiany
  align 8
  flag resd N + 1; z którym wątkiem dany chce się zamienić

global notec

extern debug

section .text

align 8

notec:
  xor ch, ch ; ustawiam flagę wpisywania na 0
  push rbp ; zachowuję rbp na stosie
  mov rbp, rsp ; początkowy licznik stosu + 1
  sub rsp, 0x20 ; trzy dodatkowe miejsca na zmienne pod stosem

  ; tych trzech rejestrów będę używać
  mov [rbp - 8], r12
  mov [rbp - 16], r13
  mov [rbp - 24], r14

  mov r12, rdi ; n - nr instancji noteci
  mov r13, rsi ; licznik literek
  ; w r14 będzie zapamiętywany wskaźnik na stos

loop:
  mov cl, [r13] ; kolejny bajt napisu
  test cl, cl ; sprawdzam czy koniec napisu
  jz kon

cyfra:
  ; sprawdzam czy cyfra 0 - 9
  cmp cl, 0x30
  jl duza
  cmp cl, 0x39
  jg duza

  sub cl, 0x30 ; '0' -> 0
  jmp dopisz

duza:
  ; sprawdzam czy litera A - F
  cmp cl, 0x41
  jl mala
  cmp cl, 0x46
  jg mala

  sub cl, 0x37 ; 'A' -> 10
  jmp dopisz

mala:
  ; sprawdzam czy litera a - f
  cmp cl, 0x61
  jl inny
  cmp cl, 0x66
  jg inny

  sub cl, 0x57 ; 'a' -> 10

dopisz:
  test ch, ch
  jnz dodaj
  push 0x0
  or ch, 0x1 ; ustawiam flagę wpisywania liczby na 1

dodaj:
  pop rdx ; zdejmuję wartość ze stosu
  shl rdx, 0x4 ; mnożę przez 16 liczbę nieujemną
  or dl, cl ; dodaję nową cyfrę
  push rdx ; wrzucam na stos
  jmp dalej

inny:
  xor ch, ch ; ustawiam flagę wpisywania liczby na 0

plus:
  cmp cl, 0x2b ; sprawdzam czy +
  jnz mno
  pop rax
  pop rdx
  add rax, rdx
  push rax
  jmp dalej

mno:
  cmp cl, 0x2a ; sprawdzam czy *
  jnz minus
  pop rax
  pop rdx
  imul rdx
  push rax
  jmp dalej

minus:
  cmp cl, 0x2d ; sprawdzam czy -
  jnz andand
  pop rdx
  xor rax, rax
  sub rax, rdx
  push rax
  jmp dalej

andand:
  cmp cl, 0x26 ; sprawdzam czy &
  jnz oror
  pop rax
  pop rdx
  and rax, rdx
  push rax
  jmp dalej

oror:
  cmp cl, 0x7c ; sprawdzam czy |
  jnz xorxor
  pop rax
  pop rdx
  or rax, rdx
  push rax
  jmp dalej

xorxor:
  cmp cl, 0x5e ; sprawdzam czy ^
  jnz notnot
  pop rax
  pop rdx
  xor rax, rdx
  push rax
  jmp dalej

notnot:
  cmp cl, 0x7e ; sprawdzam czy ~
  jnz usun
  pop rax
  not rax
  push rax
  jmp dalej

usun:
  cmp cl, 0x5a ; sprawdzam czy Z
  jnz dupl
  pop rax
  jmp dalej

dupl:
  cmp cl, 0x59 ; sprawdzam czy Y
  jnz zamien
  pop rax
  push rax
  push rax
  jmp dalej

zamien:
  cmp cl, 0x58 ; sprawdzam czy X
  jnz noteci
  pop rax
  pop rdx
  push rax
  push rdx
  jmp dalej

noteci:
  cmp cl, 0x4e ; sprawdzam czy N
  jnz inst
  ; WSTAW NA STOS LICZBĘ NOTECI
  push N
  jmp dalej

inst:
  cmp cl, 0x6e ; sprawdzam czy n
  jnz debugop 
  push r12 ; wstaw na stos nr instancji noteci
  jmp dalej

debugop:
  cmp cl, 0x67 ; sprawdzam czy g
  jnz czekaj
  ; WYWOŁAJ FUNKCJĘ DEBUG I PRZESUŃ RSP

  mov r14, rsp ; zapamiętuję wskaźnik na stos przed modyfikacją

  mov rdi, r12 ; pierwszy argument funkcji - wartość n
  mov rsi, rsp ; drugi argument funkcji - wskaźnik na stos przed modyfikacją

  and rsp, 0xFFFFFFFFFFFFFFF0 ; rsp ma być podzielne przez 16
  call debug

  mov rsp, r14 ; przywracam wskaźnik na stos
  xor rcx, rcx ; ustawiam flagę na 0

  sal rax, 0x3 ; mnożę wynik przez 8, o tyle trzeba przesunąć rsp - to mnożenie zachowuje znak
  add rsp, rax ; przesuwam rsp

  jmp dalej

czekaj:
  cmp cl, 0x57 ; sprawdzam czy W
  jnz dalej ; na razie pomijam znaki niezgodne z niczym
  ; POCZEKAJ NA NOTECIA O ODPOWIEDNIM NUMERZE I ZRÓB ZAMIANĘ WARTOŚCI NA STOSACH

  pop rax ; m - nr notecia, z którym chcę się zamienić
  pop rdx ; w - wartość do wymiany

  lea r8, [buff]
  lea r9, [flag]

  ; Uwaga: będziemy czekać na (n + 1)
  mov r10d, r12d
  add r10d, 1

  ; te movy powinny być niepodzielne
  mov [r8 + r12 * 8], rdx ; wrzucam do swojego bufora wartość do wymiany ;  buff[n] = w
  add eax, 1 ; m jest 32-bitowe i można do niego dodać 1
  mov [r9 + r12 * 4], eax ; zaznaczam z którym chcę się zamienić ;  flag[n] = m + 1
  sub eax, 1

busywait: ; while (flag[m] != n + 1) {}
  mov edx, [r9 + rax * 4] ; mov niepodzielny, zakładam że numery noteci 32-bitowe
  cmp edx, r10d
  jnz busywait

  mov rdx, [r8 + rax * 8] ; biorę wartość z bufora notecia m
  push rdx ; wrzucam ją na swój stos
  mov dword [r9 + rax * 4], 0x0 ; zaznaczam, że noteć m nie chce się już z nikim zamienić ; flag[m] = 0

; teraz muszę poczekać aż moja para weźmie wartość z mojego bufora
; żeby tam nic nie wpisać do tego czasu
busywait2: ; while (flag[n] != 0) {}
  mov edx, [r9 + r12 * 4]
  cmp edx, 0x0
  jnz busywait2

dalej: ; czytaj kolejny bajt
  add r13, 1
  jmp loop

kon:
  pop rax
  ; przywracam wartości rejestrów zgodnie z ABI
  mov r12, [rbp - 8]
  mov r13, [rbp - 16]
  mov r14, [rbp - 24]
  mov rsp, rbp
  pop rbp
  ret