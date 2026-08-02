// tools/imgdiff.cpp -- golden-image comparator.
//
// PPM in, verdict out. No image library: PPM is ~20 lines to parse and Iron
// Rule 8 makes every dependency an ADR.
//
// Reports mean absolute difference, max channel difference, and the fraction of
// pixels differing by more than a threshold -- three numbers because one is not
// enough to distinguish "the whole image shifted imperceptibly" (a driver or
// rounding change, usually benign) from "a small region changed completely"
// (a real regression, and the one that matters).
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct Image {
    int width = 0, height = 0;
    std::vector<unsigned char> px;   // RGB8
    bool ok() const { return width > 0 && height > 0; }
};

// Skips PPM comments and whitespace between header tokens.
bool next_token(std::FILE* f, long& out) {
    int c;
    for (;;) {
        c = std::fgetc(f);
        if (c == EOF) return false;
        if (c == '#') { while (c != '\n' && c != EOF) c = std::fgetc(f); continue; }
        if (std::isspace(c)) continue;
        break;
    }
    long v = 0;
    while (c != EOF && std::isdigit(c)) { v = v * 10 + (c - '0'); c = std::fgetc(f); }
    out = v;
    return true;
}

Image load_ppm(const char* path) {
    Image im;
    std::FILE* f = std::fopen(path, "rb");
    if (!f) { std::printf("imgdiff: cannot open %s\n", path); return im; }
    char magic[3] = {0, 0, 0};
    if (std::fread(magic, 1, 2, f) != 2 || magic[0] != 'P' || magic[1] != '6') {
        std::printf("imgdiff: %s is not a binary PPM (P6)\n", path);
        std::fclose(f);
        return im;
    }
    long w = 0, h = 0, maxv = 0;
    if (!next_token(f, w) || !next_token(f, h) || !next_token(f, maxv) || maxv != 255) {
        std::printf("imgdiff: %s has a malformed header\n", path);
        std::fclose(f);
        return im;
    }
    im.width = static_cast<int>(w);
    im.height = static_cast<int>(h);
    im.px.resize(static_cast<size_t>(w) * h * 3);
    if (std::fread(im.px.data(), 1, im.px.size(), f) != im.px.size()) {
        std::printf("imgdiff: %s is truncated\n", path);
        im.width = im.height = 0;
    }
    std::fclose(f);
    return im;
}

} // namespace

int main(int argc, char** argv) {
    const char* a_path = nullptr;
    const char* b_path = nullptr;
    const char* out_path = nullptr;
    double tol_mean = 0.5;      // mean abs difference, 0-255 scale
    double tol_max = 40.0;      // largest single-channel difference
    double tol_frac = 0.002;    // fraction of pixels allowed past tol_pixel
    double tol_pixel = 12.0;

    for (int i = 1; i < argc; ++i) {
        const std::string s = argv[i];
        auto val = [&](double d) { return (i + 1 < argc) ? std::atof(argv[++i]) : d; };
        if      (s == "--tol-mean")  tol_mean = val(tol_mean);
        else if (s == "--tol-max")   tol_max = val(tol_max);
        else if (s == "--tol-frac")  tol_frac = val(tol_frac);
        else if (s == "--tol-pixel") tol_pixel = val(tol_pixel);
        else if (s == "--out")       out_path = (i + 1 < argc) ? argv[++i] : nullptr;
        else if (!a_path)            a_path = argv[i];
        else if (!b_path)            b_path = argv[i];
        else { std::printf("imgdiff: unexpected argument %s\n", argv[i]); return 2; }
    }
    if (!a_path || !b_path) {
        std::printf("usage: imgdiff GOLDEN CANDIDATE [--tol-mean N] [--tol-max N]\n"
                    "                                [--tol-frac F] [--tol-pixel N]\n"
                    "                                [--out DIFF.ppm]\n");
        return 2;
    }

    const Image a = load_ppm(a_path);
    const Image b = load_ppm(b_path);
    if (!a.ok() || !b.ok()) return 2;
    if (a.width != b.width || a.height != b.height) {
        std::printf("imgdiff: FAIL size %dx%d vs %dx%d\n", a.width, a.height, b.width, b.height);
        return 1;
    }

    double sum = 0.0;
    int max_diff = 0;
    size_t bad_pixels = 0;
    const size_t n_px = static_cast<size_t>(a.width) * a.height;
    std::vector<unsigned char> diff;
    if (out_path) diff.resize(n_px * 3, 0);

    for (size_t p = 0; p < n_px; ++p) {
        int worst = 0;
        for (int c = 0; c < 3; ++c) {
            const int d = std::abs(static_cast<int>(a.px[p * 3 + c]) -
                                   static_cast<int>(b.px[p * 3 + c]));
            sum += d;
            if (d > worst) worst = d;
        }
        if (worst > max_diff) max_diff = worst;
        if (worst > tol_pixel) ++bad_pixels;
        if (out_path) {
            // Amplify so a subtle regression is actually visible in the diff.
            const unsigned char v = static_cast<unsigned char>(worst > 25 ? 255 : worst * 10);
            diff[p * 3 + 0] = v;
            diff[p * 3 + 1] = static_cast<unsigned char>(worst > tol_pixel ? 0 : v);
            diff[p * 3 + 2] = static_cast<unsigned char>(worst > tol_pixel ? 0 : v);
        }
    }

    const double mean = sum / static_cast<double>(n_px * 3);
    const double frac = static_cast<double>(bad_pixels) / static_cast<double>(n_px);

    if (out_path && !diff.empty()) {
        std::FILE* f = std::fopen(out_path, "wb");
        if (f) {
            std::fprintf(f, "P6\n%d %d\n255\n", a.width, a.height);
            std::fwrite(diff.data(), 1, diff.size(), f);
            std::fclose(f);
        }
    }

    const bool pass = mean <= tol_mean && max_diff <= tol_max && frac <= tol_frac;
    std::printf("imgdiff %s  mean %.4f (<= %.4f)  max %d (<= %.0f)  over-threshold %.4f%% (<= %.4f%%)  %s\n",
                pass ? "PASS" : "FAIL", mean, tol_mean, max_diff, tol_max,
                frac * 100.0, tol_frac * 100.0, b_path);
    return pass ? 0 : 1;
}
