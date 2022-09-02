#include <windows.h>
#include <stdio.h>
 
WINBASEAPI int __cdecl MSVCRT$printf(const char * __restrict__ _Format,...);
WINBASEAPI int __cdecl USER32$MessageBoxA(HWND hwnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);

int hey = 1000;

void go(char * args, unsigned long alen) {
    MSVCRT$printf("aa%i", hey);
    MSVCRT$printf("HELLLLLLLLLLOOOOOOOOOOO\n");
    USER32$MessageBoxA(NULL, "a", "b", S_OK);
}
