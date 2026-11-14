#pragma once

#include <algorithm>
#include <array>
#include <cmath>

namespace pulso {
enum class EqShape { lowShelf, bell, highShelf };

struct EqBand {
    EqShape shape;
    double frequency;
    double gainDb = 0;
    double q = 1;
};

class ParametricEq {
    struct Coefficients {
        std::array<double, 5> values{1, 0, 0, 0, 0};
    };
    struct Memory {
        double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    };
    struct Stage {
        Coefficients current, target;
        std::array<Memory, 2> channels{};
    };

    std::array<Stage, 6> stages_{};
    double rate_, smoothing_, mix_ = 0, output_ = 1, targetOutput_ = 1;
    bool bypass_ = true;

public:
    explicit ParametricEq(double sampleRate)
        : rate_(std::max(8000.0, sampleRate)),
          smoothing_(1 - std::exp(-1 / (0.015 * rate_))) {}

    void setBand(unsigned index, EqBand band) {
        if (index >= stages_.size() || !std::isfinite(band.frequency) ||
            !std::isfinite(band.gainDb) || !std::isfinite(band.q)) return;
        auto& target = stages_[index].target;
        if (band.gainDb == 0) {
            target = {};
            return;
        }
        const double a = std::pow(10.0, std::clamp(band.gainDb, -12.0, 12.0) / 40);
        const double w = 6.283185307179586 * std::clamp(band.frequency, 20.0, rate_ * .49) / rate_;
        const double c = std::cos(w);
        if (band.shape == EqShape::bell) {
            const double alpha = std::sin(w) / (2 * std::clamp(band.q, .1, 12.0));
            const double d = 1 + alpha / a;
            target.values = {(1 + alpha * a) / d, -2 * c / d,
                             (1 - alpha * a) / d, -2 * c / d, (1 - alpha / a) / d};
            return;
        }
        const double sign = band.shape == EqShape::lowShelf ? 1 : -1;
        const double p = a + 1, m = a - 1;
        const double t = std::sqrt(2 * a) * std::sin(w);
        const double d = p + sign * m * c + t;
        target.values = {a * (p - sign * m * c + t) / d,
                         2 * sign * a * (m - sign * p * c) / d,
                         a * (p - sign * m * c - t) / d,
                         -2 * sign * (m + sign * p * c) / d,
                         (p + sign * m * c - t) / d};
    }

    void setOutput(double gainDb, bool bypass) {
        if (std::isfinite(gainDb)) {
            targetOutput_ = std::pow(10.0, std::clamp(gainDb, -12.0, 12.0) / 20);
        }
        bypass_ = bypass;
    }

    // Planar mono o estéreo. El procesamiento no reserva memoria.
    void process(float* left, float* right, unsigned frames) {
        for (unsigned frame = 0; frame < frames; ++frame) {
            mix_ += ((bypass_ ? 0.0 : 1.0) - mix_) * smoothing_;
            output_ += (targetOutput_ - output_) * smoothing_;
            float* channels[] = {left + frame, right ? right + frame : nullptr};
            double samples[] = {*channels[0], right ? *channels[1] : 0.0};
            for (auto& stage : stages_) {
                auto& c = stage.current.values;
                for (unsigned i = 0; i < c.size(); ++i) {
                    c[i] += (stage.target.values[i] - c[i]) * smoothing_;
                }
                for (unsigned i = 0; i < (right ? 2u : 1u); ++i) {
                    auto& s = stage.channels[i];
                    const double x = samples[i];
                    const double y = c[0]*x + c[1]*s.x1 + c[2]*s.x2 - c[3]*s.y1 - c[4]*s.y2;
                    s = {x, s.x1, std::abs(y) < 1e-24 ? 0.0 : y, s.y1};
                    samples[i] = s.y1;
                }
            }
            for (unsigned i = 0; i < (right ? 2u : 1u); ++i) {
                const double dry = *channels[i];
                *channels[i] = static_cast<float>(dry + mix_ * (samples[i] * output_ - dry));
            }
        }
    }
};
}
