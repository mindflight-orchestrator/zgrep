#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <time.h>
extern bool is_ascii(const unsigned char *, size_t);
extern size_t first_zero(const unsigned char *, size_t);
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec*1e-9; }
int main(void) {
 const size_t n=9378980; unsigned char *p=malloc(n); if (!p) return 2; memset(p,'a',n);
 for(int j=0;j<2;++j) {
  double samples[15]; size_t check=0;
  for(int k=0;k<17;++k) { double start=now(); size_t x=j ? first_zero(p,n) : is_ascii(p,n); double dt=now()-start; check+=x; if(k>=2) samples[k-2]=dt*1000; }
  if (check != (j ? n : 1)*17) return 3;
  printf("%s",j ? "first_zero" : "is_ascii");
  for(int k=0;k<15;++k) printf(" %.6f",samples[k]); putchar('\n');
 }
 free(p); return 0;
}
