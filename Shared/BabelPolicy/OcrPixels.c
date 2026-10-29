#include "BabelPolicy.h"
#include <math.h>
#include <stddef.h>

/* Colour-axis separation preserves chromatic text which luminance conversion
   erases. No allocation, learned text, OS API or network in this component. */
static double component(const uint8_t *p, int channel, int format) {
    int index = (format & 1) && channel != 1 ? 2 - channel : channel;
    int alpha = p[3], value = p[index];
    return (format & 2) ? fmin(255, value + 255 - alpha) : (value * alpha + 255 * (255 - alpha)) / 255.0;
}
static int bucket(double value) {
    int n = (int)((value + 442) * 1023 / 884);
    return n < 0 ? 0 : n > 1023 ? 1023 : n;
}
int32_t bp_ocr_separate(const uint8_t *pixels, int32_t length, int32_t width, int32_t height,
                       int32_t format, uint8_t *gray, int32_t capacity) {
    int64_t count64 = (int64_t)width * height;
    if (!pixels || !gray || width <= 0 || height <= 0 || count64 > 8000000 ||
        length < count64 * 4 || capacity < count64 || format < 0 || format > 3) return 0;
    int count = (int)count64, step = count / 40000; if (step < 1) step = 1;
    double means[3] = {0}, covariance[3][3] = {{0}}, axis[3] = {.577350269, .577350269, .577350269};
    int samples = 0;
    for (int i = 0; i < count; i += step) {
        for (int c = 0; c < 3; c++) means[c] += component(pixels + (size_t)i * 4, c, format);
        samples++;
    }
    for (int c = 0; c < 3; c++) means[c] /= samples;
    for (int i = 0; i < count; i += step) {
        double delta[3];
        for (int c = 0; c < 3; c++) delta[c] = component(pixels + (size_t)i * 4, c, format) - means[c];
        for (int a = 0; a < 3; a++) for (int b = 0; b < 3; b++) covariance[a][b] += delta[a] * delta[b];
    }
    /* Start along the largest covariance column. Neutral alone can be exactly
       orthogonal to equiluminant RGB pairs and get stuck at zero variance. */
    int largest = covariance[1][1] > covariance[0][0] ? 1 : 0;
    if (covariance[2][2] > covariance[largest][largest]) largest = 2;
    if (covariance[largest][largest] < .01) return 0;
    for (int c = 0; c < 3; c++) axis[c] = c == largest ? 1 : 0;
    for (int iteration = 0; iteration < 24; iteration++) {
        double next[3] = {0}, norm = 0;
        for (int a = 0; a < 3; a++) {
            for (int b = 0; b < 3; b++) next[a] += covariance[a][b] * axis[b];
            norm += next[a] * next[a];
        }
        norm = sqrt(norm); if (norm < 1e-9) return 0;
        for (int c = 0; c < 3; c++) axis[c] = next[c] / norm;
    }
    int histogram[1024] = {0};
    for (int i = 0; i < count; i++) {
        double value = 0;
        for (int c = 0; c < 3; c++) value += component(pixels + (size_t)i * 4, c, format) * axis[c];
        histogram[bucket(value)]++;
    }
    double sum = 0, low_sum = 0, best = -1; int low_weight = 0, threshold = 0;
    for (int i = 0; i < 1024; i++) sum += (double)i * histogram[i];
    for (int i = 0; i < 1024; i++) {
        low_weight += histogram[i]; low_sum += (double)i * histogram[i];
        if (!low_weight || low_weight == count) continue;
        double difference = low_sum / low_weight - (sum - low_sum) / (count - low_weight);
        double variance = (double)low_weight * (count - low_weight) * difference * difference;
        if (variance > best) { best = variance; threshold = i; }
    }
    double a_sum = 0, b_sum = 0; int a_count = 0, b_count = 0;
    for (int i = 0; i < 1024; i++) {
        double value = i * 884.0 / 1023 - 442;
        if (i <= threshold) { a_count += histogram[i]; a_sum += value * histogram[i]; }
        else { b_count += histogram[i]; b_sum += value * histogram[i]; }
    }
    if (!a_count || !b_count) return 0;
    double a = a_sum / a_count, b = b_sum / b_count, gap = b - a;
    if (gap < .5) return 0;
    double low = a - gap * .25, span = gap * 1.5;
    int invert = a_count > b_count;
    for (int i = 0; i < count; i++) {
        double value = 0;
        for (int c = 0; c < 3; c++) value += component(pixels + (size_t)i * 4, c, format) * axis[c];
        int scaled = (int)((value - low) * 255 / span);
        if (scaled < 0) scaled = 0;
        if (scaled > 255) scaled = 255;
        gray[i] = (uint8_t)(invert ? 255 - scaled : scaled);
    }
    return 1;
}
double bp_ocr_scale(double glyph_height, int32_t cjk, int32_t width, int32_t height, int32_t maximum) {
    if (width <= 0 || height <= 0 || maximum <= 0) return 0;
    double desired = glyph_height > 0 ? (cjk ? 32.0 : 26.0) / glyph_height : 2.0;
    if (desired < 1) desired = 1;
    if (desired > 4) desired = 4;
    double dimension = (double)maximum / (width > height ? width : height);
    double budget = sqrt(8000000.0 / ((double)width * height));
    return fmin(desired, fmin(dimension, budget));
}
