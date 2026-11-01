import type {
  CouponInput
} from "./coupons.schema.js";

import {
  createCoupon,
  listCoupons,
  getCoupon,
  updateCoupon,
  changeCouponStatus,
  listCouponUses
} from "./coupons.repository.js";

export const couponsService = {

  // Crear cupon
  create(
    userId: number,
    input: CouponInput
  ) {
    return createCoupon(userId, input);
  },

  // Listar cupones
  list(
    userId: number,
    onlyActive?: boolean
  ) {
    return listCoupons(userId, onlyActive);
  },

  // Obtener cupon por ID
  get(
    userId: number,
    couponId: number
  ) {
    return getCoupon(userId, couponId);
  },

  // Actualizar cupon
  update(
    userId: number,
    couponId: number,
    input: CouponInput
  ) {
    return updateCoupon(
      userId,
      couponId,
      input
    );
  },

  // Activar o desactivar
  setActive(
    userId: number,
    couponId: number,
    active: boolean
  ) {
    return changeCouponStatus(
      userId,
      couponId,
      active
    );
  },

  // Consultar historial de usos
  uses(
    userId: number,
    couponId: number
  ) {
    return listCouponUses(
      userId,
      couponId
    );
  }

};
