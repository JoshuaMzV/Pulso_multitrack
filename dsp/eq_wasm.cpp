#include "parametric_eq.hpp"
#include <optional>

namespace {
constexpr unsigned capacity = 128;
std::optional<pulso::ParametricEq> eq;
float left[capacity], right[capacity];
}

extern "C" {
void eq_init(double rate) { eq.emplace(rate); }
float* eq_left() { return left; }
float* eq_right() { return right; }
void eq_band(unsigned index, unsigned shape, double hz, double db, double q) {
    if (eq && shape <= 2) eq->setBand(index, {static_cast<pulso::EqShape>(shape), hz, db, q});
}
void eq_output(double db, int bypass) {
    if (eq) eq->setOutput(db, bypass != 0);
}
void eq_process(unsigned frames) {
    if (eq && frames <= capacity) eq->process(left, right, frames);
}
}
