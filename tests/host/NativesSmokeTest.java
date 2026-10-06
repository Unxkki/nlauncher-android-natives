/*
 * Copyright (c) 2026 NLauncher
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Host smoke test for the libraries built with -DNL_HOST=ON.
 *
 * It loads our liblwjgl*.so / libfreetype.so / libjemalloc.so / libjnidispatch.so
 * into a desktop JVM through the stock LWJGL 3.3.3 and JNA 5.14.0 jars (no natives
 * jars on the classpath), exercises every module a little, and checks that every
 * Java "native" method of the relevant classes has a matching JNI export.
 * This proves that the per-module source lists in cmake/ are complete and match
 * the Java side; the Android build compiles the very same lists.
 *
 * Run through tests/host/run.sh (java single-file source launcher, JDK 11+).
 */
import com.sun.jna.Callback;
import com.sun.jna.Library;
import com.sun.jna.Memory;
import com.sun.jna.Native;
import com.sun.jna.Pointer;

import org.lwjgl.PointerBuffer;
import org.lwjgl.Version;
import org.lwjgl.stb.STBIWriteCallback;
import org.lwjgl.stb.STBImage;
import org.lwjgl.stb.STBImageWrite;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.jemalloc.JEmalloc;
import org.lwjgl.system.libffi.FFICIF;
import org.lwjgl.system.libffi.LibFFI;
import org.lwjgl.system.linux.DynamicLinkLoader;
import org.lwjgl.util.freetype.FT_Face;
import org.lwjgl.util.freetype.FreeType;
import org.lwjgl.util.harfbuzz.HarfBuzz;
import org.lwjgl.util.tinyfd.TinyFileDialogs;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.stream.Stream;

public class NativesSmokeTest {

    static final Path LIB_DIR = Paths.get(System.getProperty("org.lwjgl.librarypath")).toAbsolutePath();
    static int failures = 0;
    static final List<String> report = new ArrayList<>();

    interface Step { void run() throws Throwable; }

    static void step(String name, Step s) {
        try {
            s.run();
            report.add("PASS  " + name);
        } catch (Throwable t) {
            failures++;
            report.add("FAIL  " + name + " -> " + t);
            t.printStackTrace();
        }
    }

    static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) throws Exception {
        boolean haveJemalloc = Files.exists(LIB_DIR.resolve("libjemalloc.so"));
        boolean haveFreetype = Files.exists(LIB_DIR.resolve("libfreetype.so"));
        boolean haveJna = Files.exists(LIB_DIR.resolve("libjnidispatch.so"));

        step("core: Version.getVersion()", () -> {
            String v = Version.getVersion();
            System.out.println("LWJGL " + v);
            check(v.startsWith("3.3.3"), "unexpected LWJGL version " + v);
        });

        step("core: MemoryUtil alloc/calloc/realloc/aligned/free", () -> {
            System.out.println("allocator: " + MemoryUtil.getAllocator().getClass().getName());
            if (haveJemalloc) {
                check(MemoryUtil.getAllocator().getClass().getName().contains("JEmalloc"),
                      "allocator is not jemalloc");
            }
            ByteBuffer b = MemoryUtil.memAlloc(1 << 20);
            b.putLong(0, 0x1122334455667788L);
            b = MemoryUtil.memRealloc(b, 4 << 20);
            check(b.getLong(0) == 0x1122334455667788L, "realloc lost data");
            MemoryUtil.memFree(b);
            ByteBuffer c = MemoryUtil.memCalloc(4096);
            for (int i = 0; i < 4096; i++) check(c.get(i) == 0, "calloc not zeroed");
            MemoryUtil.memFree(c);
            ByteBuffer a = MemoryUtil.memAlignedAlloc(256, 1000);
            check((MemoryUtil.memAddress(a) & 255) == 0, "aligned alloc not aligned");
            MemoryUtil.memAlignedFree(a);
            try (MemoryStack stack = MemoryStack.stackPush()) {
                IntBuffer ib = stack.mallocInt(16);
                ib.put(0, 42);
                check(ib.get(0) == 42, "stack");
            }
        });

        if (haveJemalloc) {
            step("jemalloc: je_malloc/je_free_sized/je_mallocx", () -> {
                long p = JEmalloc.nje_malloc(100);
                check(p != 0, "je_malloc");
                check(JEmalloc.nje_malloc_usable_size(p) >= 100, "usable size");
                JEmalloc.nje_free_sized(p, 100);
                long q = JEmalloc.nje_aligned_alloc(64, 640);
                check(q != 0 && (q & 63) == 0, "je_aligned_alloc");
                JEmalloc.nje_free_aligned_sized(q, 64, 640);
                ByteBuffer m = JEmalloc.je_mallocx(512, 0);
                JEmalloc.je_dallocx(m, 0);
            });
        }

        step("core/libffi: ffi_prep_cif + ffi_call(strlen)", () -> {
            long libc = DynamicLinkLoader.dlopen("libc.so.6", DynamicLinkLoader.RTLD_LAZY);
            check(libc != 0, "dlopen libc");
            long strlen = DynamicLinkLoader.dlsym(libc, "strlen");
            check(strlen != 0, "dlsym strlen");
            try (MemoryStack stack = MemoryStack.stackPush()) {
                FFICIF cif = FFICIF.malloc(stack);
                PointerBuffer argTypes = stack.pointers(LibFFI.ffi_type_pointer);
                check(LibFFI.ffi_prep_cif(cif, LibFFI.FFI_DEFAULT_ABI, LibFFI.ffi_type_uint64, argTypes) == LibFFI.FFI_OK,
                      "ffi_prep_cif");
                ByteBuffer str = stack.ASCII("nlauncher-android-natives");
                PointerBuffer strPtr = stack.pointers(MemoryUtil.memAddress(str));
                PointerBuffer callArgs = stack.pointers(MemoryUtil.memAddress(strPtr));
                ByteBuffer ret = stack.malloc(8);
                LibFFI.ffi_call(cif, strlen, ret, callArgs);
                check(ret.getLong(0) == "nlauncher-android-natives".length(), "strlen via ffi_call = " + ret.getLong(0));
            }
            DynamicLinkLoader.dlclose(libc);
        });

        step("stb + libffi closures: write PNG through a callback, decode it back", () -> {
            ByteArrayOutputStream png = new ByteArrayOutputStream();
            try (MemoryStack stack = MemoryStack.stackPush();
                 STBIWriteCallback cb = STBIWriteCallback.create((ctx, data, size) -> {
                     ByteBuffer chunk = STBIWriteCallback.getData(data, size);
                     byte[] bytes = new byte[size];
                     chunk.get(bytes);
                     png.write(bytes, 0, size);
                 })) {
                ByteBuffer rgba = stack.malloc(2 * 2 * 4);
                for (int i = 0; i < 16; i++) rgba.put(i, (byte) (i * 16));
                check(STBImageWrite.stbi_write_png_to_func(cb, 0L, 2, 2, 4, rgba, 8), "stbi_write_png_to_func");
            }
            byte[] bytes = png.toByteArray();
            check(bytes.length > 8 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G', "not a PNG");
            ByteBuffer in = MemoryUtil.memAlloc(bytes.length).put(bytes).flip();
            try (MemoryStack stack = MemoryStack.stackPush()) {
                IntBuffer w = stack.mallocInt(1), h = stack.mallocInt(1), n = stack.mallocInt(1);
                ByteBuffer pixels = STBImage.stbi_load_from_memory(in, w, h, n, 4);
                check(pixels != null, "stbi_load_from_memory: " + STBImage.stbi_failure_reason());
                check(w.get(0) == 2 && h.get(0) == 2, "size");
                for (int i = 0; i < 16; i++) check(pixels.get(i) == (byte) (i * 16), "pixel " + i);
                STBImage.stbi_image_free(pixels);
            } finally {
                MemoryUtil.memFree(in);
            }
        });

        step("tinyfd: library loads, globals readable (no dialog is opened)", () -> {
            String v = TinyFileDialogs.tinyfd_getGlobalChar("tinyfd_version");
            System.out.println("tinyfd " + v);
            check(v != null && !v.isEmpty(), "tinyfd_version");
        });

        if (haveFreetype) {
            step("freetype: FT_Init_FreeType / FT_Library_Version / FT_Done_FreeType", () -> {
                try (MemoryStack stack = MemoryStack.stackPush()) {
                    PointerBuffer lib = stack.mallocPointer(1);
                    check(FreeType.FT_Init_FreeType(lib) == 0, "FT_Init_FreeType");
                    IntBuffer ma = stack.mallocInt(1), mi = stack.mallocInt(1), pa = stack.mallocInt(1);
                    FreeType.FT_Library_Version(lib.get(0), ma, mi, pa);
                    String v = ma.get(0) + "." + mi.get(0) + "." + pa.get(0);
                    System.out.println("FreeType " + v);
                    check(v.equals("2.13.2"), "FreeType version " + v);
                    Path font = findFont();
                    if (font != null) {
                        byte[] fb = Files.readAllBytes(font);
                        ByteBuffer fbuf = MemoryUtil.memAlloc(fb.length).put(fb).flip();
                        PointerBuffer face = stack.mallocPointer(1);
                        check(FreeType.FT_New_Memory_Face(lib.get(0), fbuf, 0, face) == 0, "FT_New_Memory_Face " + font);
                        FT_Face f = FT_Face.create(face.get(0));
                        check(FreeType.FT_Set_Pixel_Sizes(f, 0, 32) == 0, "FT_Set_Pixel_Sizes");
                        check(FreeType.FT_Load_Char(f, 'A', FreeType.FT_LOAD_RENDER) == 0, "FT_Load_Char");
                        int bw = f.glyph().bitmap().width(), bh = f.glyph().bitmap().rows();
                        System.out.println("rendered 'A' from " + font.getFileName() + ": " + bw + "x" + bh);
                        check(bw > 0 && bh > 0, "empty glyph bitmap");
                        check(FreeType.FT_Done_Face(f) == 0, "FT_Done_Face");
                        MemoryUtil.memFree(fbuf);
                    } else {
                        System.out.println("no .ttf font found, glyph rendering skipped");
                    }
                    check(FreeType.FT_Done_FreeType(lib.get(0)) == 0, "FT_Done_FreeType");
                }
            });

            step("harfbuzz (inside libfreetype.so): version + shaping", () -> {
                org.lwjgl.system.Configuration.HARFBUZZ_LIBRARY_NAME.set(FreeType.getLibrary());
                String v = HarfBuzz.hb_version_string();
                System.out.println("HarfBuzz " + v);
                check(v.equals("8.2.0"), "HarfBuzz version " + v);
                Path font = findFont();
                if (font != null) {
                    byte[] fb = Files.readAllBytes(font);
                    ByteBuffer fbuf = MemoryUtil.memAlloc(fb.length).put(fb).flip();
                    long blob = HarfBuzz.hb_blob_create(fbuf, HarfBuzz.HB_MEMORY_MODE_READONLY, 0L, null);
                    long face = HarfBuzz.hb_face_create(blob, 0);
                    long hbFont = HarfBuzz.hb_font_create(face);
                    long buf = HarfBuzz.hb_buffer_create();
                    HarfBuzz.hb_buffer_add_utf8(buf, "Hello", 0, -1);
                    HarfBuzz.hb_buffer_guess_segment_properties(buf);
                    HarfBuzz.hb_shape(hbFont, buf, null);
                    int glyphs = HarfBuzz.hb_buffer_get_length(buf);
                    System.out.println("shaped 'Hello' -> " + glyphs + " glyphs");
                    check(glyphs == 5, "hb_shape glyph count " + glyphs);
                    HarfBuzz.hb_buffer_destroy(buf);
                    HarfBuzz.hb_font_destroy(hbFont);
                    HarfBuzz.hb_face_destroy(face);
                    HarfBuzz.hb_blob_destroy(blob);
                    MemoryUtil.memFree(fbuf);
                }
            });
        }

        if (haveJna) {
            step("jna: libjnidispatch loads from jna.boot.library.path, calls + callbacks work", JnaTest::run);
        }

        // ---- JNI export check: every native method in the jars must resolve -------------
        String cp = System.getProperty("java.class.path");
        for (String jar : cp.split(java.io.File.pathSeparator)) {
            String name = Paths.get(jar).getFileName().toString();
            String lib = libraryForJar(name);
            if (lib == null || !Files.exists(LIB_DIR.resolve(lib))) continue;
            step("JNI exports: " + name + " -> " + lib, () -> checkJniExports(Paths.get(jar), LIB_DIR.resolve(lib)));
        }

        step("only our libraries were loaded", () -> {
            List<String> maps = Files.readAllLines(Paths.get("/proc/self/maps"));
            for (String lib : new String[] {"liblwjgl.so", "liblwjgl_stb.so", "liblwjgl_tinyfd.so", "libjemalloc.so",
                                            "libfreetype.so", "libjnidispatch.so"}) {
                if (!Files.exists(LIB_DIR.resolve(lib))) continue;
                boolean ours = false;
                for (String line : maps) {
                    if (!line.endsWith("/" + lib)) continue;
                    String path = line.substring(line.indexOf('/'));
                    check(Paths.get(path).startsWith(LIB_DIR), lib + " mapped from " + path);
                    ours = true;
                }
                check(ours, lib + " is not mapped");
            }
        });

        System.out.println();
        System.out.println("==== host natives smoke test ====");
        report.forEach(System.out::println);
        System.out.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        System.exit(failures == 0 ? 0 : 1);
    }

    static Path findFont() throws IOException {
        String env = System.getenv("NL_TEST_FONT");
        if (env != null && !env.isEmpty()) return Paths.get(env);
        Path root = Paths.get("/usr/share/fonts");
        if (!Files.isDirectory(root)) return null;
        try (Stream<Path> s = Files.walk(root)) {
            return s.filter(p -> p.toString().endsWith(".ttf")).sorted().findFirst().orElse(null);
        }
    }

    static String libraryForJar(String jar) {
        if (jar.startsWith("lwjgl-opengl-")) return "liblwjgl_opengl.so";
        if (jar.startsWith("lwjgl-stb-")) return "liblwjgl_stb.so";
        if (jar.startsWith("lwjgl-tinyfd-")) return "liblwjgl_tinyfd.so";
        if (jar.matches("lwjgl-3\\..*\\.jar")) return "liblwjgl.so";
        if (jar.startsWith("jna-")) return "libjnidispatch.so";
        return null; // freetype/harfbuzz/jemalloc bindings have no JNI code
    }

    /** Classes whose natives are intentionally not compiled for Linux/Android. */
    static boolean skipClass(String cls) {
        return cls.startsWith("org.lwjgl.system.windows.")
            || cls.startsWith("org.lwjgl.system.macosx.")
            || cls.startsWith("org.lwjgl.system.freebsd.")
            || cls.startsWith("org.lwjgl.system.jawt.")      // NL_LWJGL_JAWT=OFF: no AWT on Android
            || cls.startsWith("org.lwjgl.opengl.WGL")         // excluded by upstream on Linux too
            || cls.startsWith("org.lwjgl.opengl.CGL")
            || cls.startsWith("com.sun.jna.win32.");
    }

    static void checkJniExports(Path jar, Path lib) throws Exception {
        long handle = DynamicLinkLoader.dlopen(lib.toString(), DynamicLinkLoader.RTLD_LAZY | DynamicLinkLoader.RTLD_LOCAL);
        check(handle != 0, "dlopen " + lib);
        int natives = 0;
        Map<String, List<String>> missing = new TreeMap<>();
        ClassLoader cl = NativesSmokeTest.class.getClassLoader();
        try (JarFile jf = new JarFile(jar.toFile())) {
            for (Enumeration<JarEntry> e = jf.entries(); e.hasMoreElements(); ) {
                String n = e.nextElement().getName();
                if (!n.endsWith(".class") || n.startsWith("META-INF/") || n.endsWith("module-info.class")) continue;
                String cls = n.substring(0, n.length() - 6).replace('/', '.');
                if (skipClass(cls)) continue;
                Class<?> c;
                try {
                    c = Class.forName(cls, false, cl);
                } catch (Throwable t) {
                    continue; // e.g. optional dependencies of unrelated classes
                }
                Method[] methods;
                try {
                    methods = c.getDeclaredMethods();
                } catch (Throwable t) {
                    continue;
                }
                for (Method m : methods) {
                    if (!Modifier.isNative(m.getModifiers())) continue;
                    natives++;
                    String shortName = "Java_" + mangle(c.getName()) + "_" + mangle(m.getName());
                    if (DynamicLinkLoader.dlsym(handle, shortName) != 0) continue;
                    String longName = shortName + "__" + mangle(argSignature(m));
                    if (DynamicLinkLoader.dlsym(handle, longName) != 0) continue;
                    missing.computeIfAbsent(c.getName(), k -> new ArrayList<>()).add(m.getName());
                }
            }
        }
        DynamicLinkLoader.dlclose(handle);
        System.out.println(jar.getFileName() + ": " + natives + " native methods checked against " + lib.getFileName());
        check(natives > 0, "no native methods found in " + jar);
        check(missing.isEmpty(), "missing JNI exports: " + missing);
    }

    static String argSignature(Method m) {
        StringBuilder sb = new StringBuilder();
        for (Class<?> p : m.getParameterTypes()) sb.append(descriptor(p));
        return sb.toString();
    }

    static String descriptor(Class<?> c) {
        if (c.isArray()) return c.getName().replace('.', '/');
        if (c == int.class) return "I";
        if (c == long.class) return "J";
        if (c == boolean.class) return "Z";
        if (c == byte.class) return "B";
        if (c == char.class) return "C";
        if (c == short.class) return "S";
        if (c == float.class) return "F";
        if (c == double.class) return "D";
        if (c == void.class) return "V";
        return "L" + c.getName().replace('.', '/') + ";";
    }

    /** JNI name mangling (JNI spec, "Resolving Native Method Names"). */
    static String mangle(String s) {
        StringBuilder sb = new StringBuilder();
        for (char ch : s.toCharArray()) {
            if (ch == '.' || ch == '/') sb.append('_');
            else if (ch == '_') sb.append("_1");
            else if (ch == ';') sb.append("_2");
            else if (ch == '[') sb.append("_3");
            else if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) sb.append(ch);
            else sb.append(String.format("_0%04x", (int) ch));
        }
        return sb.toString();
    }

    // ---- JNA ------------------------------------------------------------------------
    public interface CLib extends Library {
        int getpid();
        long strlen(String s);
        void qsort(Pointer base, long n, long size, Comparator cmp);
        interface Comparator extends Callback { int compare(Pointer a, Pointer b); }
    }

    static class JnaTest {
        static void run() throws Exception {
            int ps = Native.POINTER_SIZE; // static init: loads libjnidispatch and checks its version
            java.lang.reflect.Field f = Native.class.getDeclaredField("jnidispatchPath");
            f.setAccessible(true);
            String path = (String) f.get(null);
            System.out.println("JNA " + Native.VERSION + " (native " + Native.VERSION_NATIVE + "), jnidispatch: " + path);
            check(path != null && Paths.get(path).toAbsolutePath().startsWith(LIB_DIR), "jnidispatch loaded from " + path);
            check(ps == 8, "POINTER_SIZE");
            CLib c = Native.load("c", CLib.class);
            check(c.getpid() == ProcessHandle.current().pid(), "getpid");
            check(c.strlen("android") == 7, "strlen");
            Memory mem = new Memory(4L * 5);
            int[] in = {5, 3, 9, 1, 7};
            mem.write(0, in, 0, in.length);
            c.qsort(mem, in.length, 4, (a, b) -> Integer.compare(a.getInt(0), b.getInt(0)));
            int[] out = mem.getIntArray(0, in.length);
            check(java.util.Arrays.equals(out, new int[] {1, 3, 5, 7, 9}), "qsort via JNA callback: " + java.util.Arrays.toString(out));
        }
    }
}
