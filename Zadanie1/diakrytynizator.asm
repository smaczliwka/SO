SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT  equ 60
STDIN equ 0
STDOUT equ 1

; Wykonanie programu zaczyna się od etykiety _start.
global _start

section .rodata
    PODSTAWA equ 0xA
    MODULO equ 0x10FF80
    BUFF_SIZE equ 2048 ; Uwaga: rozmiar bufora powinien być większy niż maksymalna liczba bajtów literki w UTF-8

section .bss
    buff resb BUFF_SIZE,
    buffout resb BUFF_SIZE

section .text

_start:

  xor r13, r13 ; ten bajt z buff obecnie przetwarzamy
  xor r14, r14 ; tyle bajtów wczytał syscall

  xor r15, r15; pozycja następnego bajtu do wpisania do buffout

  xor r8, r8 ; tu trzymamy wartość unicode znaku
  
  mov r9, [rsp] ; liczba parametrów
  cmp r9, 1
  jle wrong
  
  shl r9, 3 ; liczba paramterów razy 8

  lea     rbp, [rsp + 8]  ; adres args[0] 
  jmp param_pierwszy

  ; w [rsp] liczba argumentów + 1 (bo jeszcze nazwa programu)
  
; PRZETWARZANIE PARAMETRÓW

param:
  mov [rbp], eax ; Uwaga: komórka 8 bajtowa, a wpisuję tam wartość 4 bajtową

param_pierwszy: ; pierwszy argument - pomijam zapisanie wartości poprzedniego

  add     rbp, 8          ; Przejdź do następnego argumentu - pomija nazwę programu
  mov     rsi, [rbp]      ; adres kolejnego argumentu
  test    rsi, rsi
  jz      wczytaj_bufor   ; Napotkano zerowy wskaźnik, nie ma więcej argumentów.

  xor rax, rax ; argument jako liczba, na początku 0

param_nast:

  ; sprawdzam czy koniec argumentu
  cmp byte [rsi], 0x0
  jz param

  ; sprawdzam czy poprawna cyferka
  cmp byte [rsi], 0x30
  jl wrong
  cmp byte [rsi], 0x39
  jg wrong

  mov ecx, PODSTAWA ; mnożę razy 10
  mul ecx
  xor ecx, ecx ; zeruję ecx
  mov cl, byte [rsi]
  sub cl, 0x30
  add eax, ecx ; dodaję następną cyfrę

  ; moduluję współczynnik wielomianu
  mov ecx, MODULO
  div ecx
  mov eax, edx ; zostawiam resztę z dzielenia jako wynik

  add rsi, 1; przesuń adres o jeden
  jmp param_nast

znak: ; pętla dla kolejnych literek - wartości unicode
 
  ; być może kodowane na 4 bajtach, ale wciąż za duża wartość
  cmp r8, 0x10FFFF
  jg wrong

  ; trzeba jeszcze sprawdzić, czy kodowanie jest minimalnym możliwym
  cmp r12b, 3
  jg wrong

  cmp r8, 0x10000
  jge wielomian
  
  cmp r12b, 2
  jg wrong

  cmp r8, 0x800
  jge wielomian

  cmp r12b, 1
  jg wrong

  cmp r8, 0x80
  jge wielomian

  cmp r12b, 0
  jg wrong

  ; LICZENIE WIELOMIANU

wielomian:

  ; jeśli wartość z przedziału 0x00 - 0x7F, to zostaje bez zmian
  cmp r8, 0x7F
  jle konwertuj

  sub r8, 0x80 ; wynik na pewno większy równy 0
  
  ; moduluję wartość unicode
  mov rax, r8
  xor rdx, rdx
  mov rcx, MODULO
  div rcx
  mov r8, rdx ; zostawiam resztę z dzielenia jako wynik
  ; teraz r8 < MODULO

  xor rax, rax ; w rax będzie wynik mnożenia

  lea rbp, [rsp + 8]
  add rbp, r9
  mov r10, r9

wielomian_dalej:
  ; na początku rax < MODULO - mieści się całe w eax

  cmp r10, 8
  jz zamiana_wart

  sub rbp, 8 ; bo rbp skończyło na pustym
  sub r10, 8
  
  xor rdx, rdx ; zeruję rdx potrzebny do mnożenia
  mul r8
  ; teraz rax <= (MODULO - 1) * (MODULO - 1) - wynik mnożenia mieści się w rax
  
  ; moduluję wynik
  xor rdx, rdx
  mov rcx, MODULO
  div rcx
  mov rax, rdx ; zostawiam resztę z dzielenia jako wynik

  ; teraz rax < MODULO - mieści się całe w eax

  add eax, [rbp] ; teraz w eax maksymalnie 2 * MODULO - 2

  ; znowu moduluję wynik
  xor rdx, rdx
  mov rcx, MODULO
  div rcx
  mov rax, rdx ; zostawiam resztę z dzielenia jako wynik

  jmp wielomian_dalej

zamiana_wart:
  mov r8, rax
  add r8, 0x80
  
konwertuj:
  
  ; KONWERTOWANIE UNICODE NA UTF-8

  mov bl, 0xfc ; 1111 110x prefiks
  mov bh, 6 ; tyle bajtów łącznie z pierwszym
  cmp r8, 0x4000000 ; 2 ^ 26
  jge modyfikuj

  shl bl, 1
  sub bh, 1
  cmp r8, 0x200000; 2 ^ 21
  jge modyfikuj

  shl bl, 1
  sub bh, 1
  cmp r8, 0x10000 ; 2 ^ 16
  jge modyfikuj

  shl bl, 1
  sub bh, 1
  cmp r8, 0x800 ; 2 ^ 11
  jge modyfikuj

  shl bl, 1 ; 110x xxxx
  sub bh, 1 
  cmp r8, 0x80 ; 2 ^ 7
  jge modyfikuj

  shl bl, 2 ; 0xxx xxxx
  sub bh, 1 ; teraz jeden

modyfikuj:
  ; zapisuję liczbę bajtów literki w UTF-8 do rdx
  xor rdx, rdx
  or dl, bh

  add rdx, r15 ; teraz w rdx pozycja za ostatnim bajtem tej literki
  cmp rdx, BUFF_SIZE
  jle kolejny_bajt

  ; wypisuję bufor, bo nowa literka się nie zmieści
  mov rdx, r15
  mov rsi, buffout
  mov rdi, STDOUT
  mov rax, SYS_WRITE
  syscall

  xor r15, r15 ; buffout teraz pusty

  ; zapisuję liczbę bajtów literki w UTF-8 do rdx
  xor rdx, rdx ; teraz w rdx pozycja za ostatnim bajtem tej literki
  or dl, bh

kolejny_bajt:
  sub bh, 1
  cmp bh, 0
  jz pierwszy_bajt
  
  ; dodaję prefiks 10 do ostatniego bajtu
  shl r8, 2 
  shr r8b, 2
  or r8b, 0x80

  ; przenoszę numer bajtu do rcx
  xor rcx, rcx
  or cl, bh

  mov [buffout + r15 + rcx], r8b
  shr r8, 8

  jmp kolejny_bajt

pierwszy_bajt:
  or r8b, bl ; oruję z odpowiednim prefiksem
  mov [buffout + r15], r8b
  shr r8, 8 ; po tym kroku r8 powinno być 0

  mov r15, rdx ; teraz w r15 pozycja za ostatnim bajtem tej literki

  cmp r13d, r14d ; mogę porównywać młodsze części, i tak rozmiar bufora max. 32-bitowy
  jl kolejna_litera

wczytaj_bufor:

  mov     rax, SYS_READ
  mov     rdi, STDIN
  mov     rdx, BUFF_SIZE          ; Wczytaj cały bufor.
  mov rsi, buff
  syscall

  cmp rax, 0
  jz exit

  ; EOT ZAJMUJE 1 DODATKOWY BAJT!!!

  mov r14, rax
  xor r13, r13
  
kolejna_litera:

  ; szukamy pierwszego od lewej zera
  mov bl, byte [buff + r13]

  mov bh, 3 ; tyle bajtów będzie jeszcze do wczytania
  shr bl, 3 ; przesuwam w prawo o 3 bity
  cmp bl, 0x1e ; jeszcze 3 bajty do wcztania
  jz reszta_litery

  sub bh, 1
  shr bl, 1 ; przesuwam w prawo o 1 bit
  cmp bl, 0xe ; jeszcze 2 bajty do wcztania
  jz reszta_litery

  sub bh, 1
  shr bl, 1 ; przesuwam w prawo o 1 bit
  cmp bl, 0x6 ; jeszcze 1 bajt do wcztania
  jz reszta_litery

  sub bh, 1
  shr bl, 2
  cmp bl, 0 ; pierwsze musi być 0, wpp zły format
  jnz wrong

reszta_litery: ; wczytuje dalsze bajty tej samej literki

  mov r8, 0
  mov r8b, byte [buff + r13] ; w r8 będzie wartość Unicode literki
  add r13, 1

  mov cl, bh
  mov r12b, cl ; długość w bajtach do sprawdzenia, czy zapis minimalny

  cmp bh, 0
  jz czytaj_bajt ; nie trzeba nic ucinać

  ; ucinam prefiks złożony z jedynek
  shl r8b, cl
  shl r8b, 1
  shr r8b, cl
  shr r8b, 1

czytaj_bajt:
  
  cmp bh, 0
  jz znak
  sub bh, 1  

  cmp r13d, r14d ; mogę porównywać młodsze części, i tak rozmiar bufora max. 32-bitowy
  jl niewczytuj_buff

  cmp r14, BUFF_SIZE ; Czy ostatni bufor wczytał się cały? Jeśli nie, to reszta_litery danych.
  jl wrong

  mov     rax, SYS_READ
  mov     rdi, STDIN
  mov     rdx, BUFF_SIZE          ; Wczytaj cały bufor.
  mov rsi, buff
  syscall

  cmp rax, 0 ; powinno być coś jeszcze
  jz wrong

  mov r14, rax
  xor r13, r13

niewczytuj_buff:

  ; sprawdza czy poprawny format kolejnego bajtu
  mov bl, byte [buff + r13]
  shr bl, 6
  cmp bl, 0x2
  jnz wrong

  mov bl, byte [buff + r13]
  ; ucinam dwie pierwsze cyfry bajtu
  shl bl, 2
  shr bl, 2
  ; przesuwam r8 o 6 bitów - tyle będzie dostawionych
  shl r8, 6
  or r8b, bl

  add r13, 1
  jmp czytaj_bajt

; Po stwierdzeniu błędnego wejścia wypisuję cały buffout i kończę program z kodem 1.
wrong:
  mov rdx, r15
  mov rsi, buffout
  mov rdi, STDOUT
  mov rax, SYS_WRITE
  syscall

  mov     eax, SYS_EXIT
  mov edi, 1
  syscall
  
exit:
  mov rdx, r15
  mov rsi, buffout
  mov rdi, STDOUT
  mov rax, SYS_WRITE
  syscall
  
  mov     eax, SYS_EXIT
  xor     edi, edi        ; kod powrotu 0
  syscall