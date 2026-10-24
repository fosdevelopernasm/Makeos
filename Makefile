ASM := nasm
CC := gcc
LD := ld

ASMFLAGS := -f elf32
CFLAGS := -m32 -ffreestanding -fno-pic -fno-stack-protector -nostdlib -Wall -Wextra -O2
LDFLAGS := -m elf_i386 -T linker.ld

BUILD := build
SRC := src

ASM_SRCS := $(SRC)/boot.asm
C_SRCS := $(SRC)/kernel.c

ASM_OBJS := $(patsubst $(SRC)/%.asm,$(BUILD)/%.o,$(ASM_SRCS))
C_OBJS := $(patsubst $(SRC)/%.c,$(BUILD)/%.o,$(C_SRCS))
OBJS := $(ASM_OBJS) $(C_OBJS)

KERNEL := $(BUILD)/kernel.elf
ISO := $(BUILD)/myos.iso

GEN_FILES := $(SRC)/boot.asm $(SRC)/kernel.c linker.ld grub.cfg .github/workflows/build.yml

.PHONY: all clean iso run gen

all: gen $(KERNEL)

gen: $(GEN_FILES)

$(SRC)/boot.asm:
	@mkdir -p $(SRC)
	@printf '%s\n' \
	'BITS 32' \
	'' \
	'section .multiboot_header' \
	'align 8' \
	'header_start:' \
	'    dd 0xe85250d6' \
	'    dd 0' \
	'    dd header_end - header_start' \
	'    dd 0x100000000 - (0xe85250d6 + 0 + (header_end - header_start))' \
	'' \
	'    align 8' \
	'    dw 5' \
	'    dw 0' \
	'    dd 20' \
	'    dd 0' \
	'    dd 0' \
	'    dd 0' \
	'' \
	'    align 8' \
	'    dw 0' \
	'    dw 0' \
	'    dd 8' \
	'header_end:' \
	'' \
	'section .bss' \
	'align 16' \
	'stack_bottom:' \
	'    resb 16384' \
	'stack_top:' \
	'' \
	'section .text' \
	'global _start' \
	'extern kmain' \
	'' \
	'_start:' \
	'    cli' \
	'    mov esp, stack_top' \
	'    push ebx' \
	'    push eax' \
	'    call kmain' \
	'' \
	'.hang:' \
	'    hlt' \
	'    jmp .hang' \
	> $@

$(SRC)/kernel.c:
	@mkdir -p $(SRC)
	@printf '%s\n' \
	'#include <stdint.h>' \
	'' \
	'#define VGA_TEXT_BASE 0xB8000' \
	'#define VGA_TEXT_COLS 80' \
	'#define VGA_TEXT_ROWS 25' \
	'#define VGA_GFX_BASE  0xA0000' \
	'#define VGA_GFX_W     320' \
	'#define VGA_GFX_H     200' \
	'' \
	'#define MULTIBOOT2_BOOTLOADER_MAGIC 0x36d76289' \
	'' \
	'struct mb2_tag {' \
	'    uint32_t type;' \
	'    uint32_t size;' \
	'};' \
	'' \
	'static volatile uint16_t *const vga_text = (volatile uint16_t *)VGA_TEXT_BASE;' \
	'static volatile uint8_t *const vga_gfx = (volatile uint8_t *)VGA_GFX_BASE;' \
	'' \
	'static void text_clear(void) {' \
	'    for (uint32_t i = 0; i < VGA_TEXT_COLS * VGA_TEXT_ROWS; i++)' \
	'        vga_text[i] = 0x0F20;' \
	'}' \
	'' \
	'static void text_puts(const char *s) {' \
	'    uint32_t pos = 0;' \
	'    while (*s) {' \
	'        char c = *s++;' \
	'        if (c == 0x0A) {' \
	'            pos += VGA_TEXT_COLS - (pos % VGA_TEXT_COLS);' \
	'            continue;' \
	'        }' \
	'        vga_text[pos++] = (uint16_t)0x0F00 | (uint8_t)c;' \
	'        if (pos >= VGA_TEXT_COLS * VGA_TEXT_ROWS) pos = 0;' \
	'    }' \
	'}' \
	'' \
	'static void gfx_clear(uint8_t color) {' \
	'    for (uint32_t i = 0; i < VGA_GFX_W * VGA_GFX_H; i++)' \
	'        vga_gfx[i] = color;' \
	'}' \
	'' \
	'static void gfx_putpixel(uint32_t x, uint32_t y, uint8_t color) {' \
	'    if (x < VGA_GFX_W && y < VGA_GFX_H)' \
	'        vga_gfx[y * VGA_GFX_W + x] = color;' \
	'}' \
	'' \
	'static void gfx_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint8_t color) {' \
	'    for (uint32_t j = 0; j < h; j++)' \
	'        for (uint32_t i = 0; i < w; i++)' \
	'            gfx_putpixel(x + i, y + j, color);' \
	'}' \
	'' \
	'static void normal_mode(void) {' \
	'    text_clear();' \
	'    text_puts("MyOS - Normal Mode\n");' \
	'    text_puts("VGA text 80x25\n");' \
	'    text_puts("Kernel running.\n");' \
	'}' \
	'' \
	'static void vga_mode(void) {' \
	'    gfx_clear(0x00);' \
	'    gfx_rect(10, 10, 100, 50, 0x0F);' \
	'    gfx_rect(150, 10, 100, 50, 0x04);' \
	'    gfx_rect(10, 100, 240, 60, 0x02);' \
	'    gfx_rect(60, 40, 40, 80, 0x0E);' \
	'}' \
	'' \
	'void kmain(uint32_t magic, void *mb_info) {' \
	'    if (magic != MULTIBOOT2_BOOTLOADER_MAGIC) {' \
	'        normal_mode();' \
	'        for (;;) __asm__ volatile("hlt");' \
	'    }' \
	'' \
	'    uint8_t *p = (uint8_t *)mb_info;' \
	'    uint32_t total = *(uint32_t *)p;' \
	'    p += 8;' \
	'' \
	'    uint8_t fb_present = 0;' \
	'    while ((uint32_t)(p - (uint8_t *)mb_info) < total) {' \
	'        struct mb2_tag *tag = (struct mb2_tag *)p;' \
	'        if (tag->type == 0) break;' \
	'        if (tag->type == 8) { fb_present = 1; break; }' \
	'        p += (tag->size + 7) & ~7u;' \
	'    }' \
	'' \
	'    if (fb_present) vga_mode();' \
	'    else normal_mode();' \
	'' \
	'    for (;;) __asm__ volatile("hlt");' \
	'}' \
	> $@

linker.ld:
	@printf '%s\n' \
	'ENTRY(_start)' \
	'' \
	'SECTIONS {' \
	'    . = 1M;' \
	'    .multiboot_header : { KEEP(*(.multiboot_header)) }' \
	'    .text : { *(.text) }' \
	'    .rodata : { *(.rodata) }' \
	'    .data : { *(.data) }' \
	'    .bss : { *(COMMON) *(.bss) }' \
	'}' \
	> $@

grub.cfg:
	@printf '%s\n' \
	'set timeout=5' \
	'set default=0' \
	'' \
	'menuentry "MyOS normal mode" {' \
	'    multiboot2 /boot/kernel.elf' \
	'    boot' \
	'}' \
	'' \
	'menuentry "MyOS vga mode" {' \
	'    multiboot2 /boot/kernel.elf' \
	'    set gfxpayload=320x200x8' \
	'    boot' \
	'}' \
	> $@

.github/workflows/build.yml:
	@mkdir -p .github/workflows
	@printf '%s\n' \
	'name: build' \
	'' \
	'on:' \
	'  push:' \
	'    branches: [main]' \
	'  pull_request:' \
	'    branches: [main]' \
	'' \
	'jobs:' \
	'  build:' \
	'    runs-on: ubuntu-latest' \
	'    steps:' \
	'      - uses: actions/checkout@v4' \
	'      - name: Install deps' \
	'        run: |' \
	'          sudo apt-get update' \
	'          sudo apt-get install -y nasm gcc-multilib binutils grub-pc-bin grub-common xorriso mtools' \
	'      - name: Build' \
	'        run: make' \
	'      - name: Build ISO' \
	'        run: make iso' \
	'      - name: Upload' \
	'        uses: actions/upload-artifact@v4' \
	'        with:' \
	'          name: myos-iso' \
	'          path: build/myos.iso' \
	> $@

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/%.o: $(SRC)/%.asm | $(BUILD)
	$(ASM) $(ASMFLAGS) $< -o $@

$(BUILD)/%.o: $(SRC)/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(KERNEL): $(OBJS) linker.ld
	$(LD) $(LDFLAGS) -o $@ $(OBJS)

iso: gen $(ISO)

$(ISO): $(KERNEL) grub.cfg
	@mkdir -p $(BUILD)/iso/boot/grub
	cp $(KERNEL) $(BUILD)/iso/boot/kernel.elf
	cp grub.cfg $(BUILD)/iso/boot/grub/grub.cfg
	grub-mkrescue -o $(ISO) $(BUILD)/iso

run: $(ISO)
	qemu-system-i386 -cdrom $(ISO)

clean:
	rm -rf $(BUILD) $(GEN_FILES)
