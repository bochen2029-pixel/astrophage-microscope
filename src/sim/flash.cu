// src/sim/flash.cu -- the spin-drive flash (PHYSICS.md Sec 6, ADR-033).
//
// While w.flash_active, an external high-intensity Petrova-band pulse forces every awake
// charged cell to discharge its store at full rate as Petrova photons directed at the
// slide: dE/dt = -emit_power, and the recoil thrust = emit_power / C_LIGHT is applied by
// motion_step from the emit_power/axis this stage writes. The delivered momentum and the
// discharged energy accumulate into w.d_flash_accum in fixed point (INV-2), and
// impulse_per_cycle = |impulse| * C_LIGHT / discharged is asserted ~= 1 (accept): a
// photon-momentum identity that also catches any axis incoherence.
#include <cmath>
#include <cstdint>

#include <cuda_runtime.h>

#include "contracts/cell_store_v1.h"
#include "core/canon_generated.h"
#include "core/fixed_atomic.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

// Fixed-point scales for the flash audit (determinism plumbing like the field deposit
// scales in fields_v1.h, not physical constants -- hence the explicit waiver). Total over
// a full population's discharge: energy ~1.5e9 J, impulse ~5 N*s, both far inside int64.
static constexpr double FLASH_IMPULSE_SCALE = 1.0e15;  // ASTRO_LITERAL_OK N*s -> int64
static constexpr double FLASH_ENERGY_SCALE  = 1.0e6;   // J -> int64 (as DEPOSIT_SCALE_STATS)

namespace {

__global__ void flash_kernel(CellStoreView v, double dt, double flash_power,
                             unsigned long long* accum) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE) || !(f & CELL_FLAG_AWAKE)) return;

    double e = v.energy[i];
    v.emit_power[i] = 0.0f;                    // no FREE-cell thrust (see below)
    if (e <= 0.0) return;
    double power = flash_power;
    double de = power * dt;
    if (de > e) de = e;                        // cannot emit more than the store holds
    v.energy[i] = e - de;

    // The cell is fixed to the drive face, so its recoil drives the SHIP, not the free
    // cell -- hence emit_power stays 0 (a 16.7 ng mass-energy discharge would otherwise
    // recoil a lone 10 um cell at ~c). The impulse is accounted here for the HUD: every
    // cell discharges toward the objective (+z), so the recoils add coherently along -z,
    // which is the whole point of a spin drive.
    const double imp = de / canon::C_LIGHT;   // photon momentum = E/C_LIGHT
    atomic_deposit(&accum[2], -imp, FLASH_IMPULSE_SCALE);   // imp_z (x,y stay 0)
    atomic_deposit(&accum[3],  de,  FLASH_ENERGY_SCALE);    // discharged
}

}  // namespace

void flash_step(World& w, double dt) {
    const int32_t n = w.cells.count;
    if (!w.flash_active || n <= 0 || w.d_flash_accum == nullptr) return;
    const int block = 256;
    const int grid = (n + block - 1) / block;
    flash_kernel<<<grid, block>>>(w.cells.view, dt, canon::PETROVA_FLASH_POWER, w.d_flash_accum);
}

void world_flash_audit(const World& w, double& impulse_ns, double& discharged_j) {
    unsigned long long raw[4] = {0, 0, 0, 0};
    if (w.d_flash_accum != nullptr)
        cudaMemcpy(raw, w.d_flash_accum, sizeof(raw), cudaMemcpyDeviceToHost);
    const double ix = from_fixed(raw[0], FLASH_IMPULSE_SCALE);
    const double iy = from_fixed(raw[1], FLASH_IMPULSE_SCALE);
    const double iz = from_fixed(raw[2], FLASH_IMPULSE_SCALE);
    impulse_ns   = std::sqrt(ix * ix + iy * iy + iz * iz);
    discharged_j = from_fixed(raw[3], FLASH_ENERGY_SCALE);
}

} // namespace astro::sim
