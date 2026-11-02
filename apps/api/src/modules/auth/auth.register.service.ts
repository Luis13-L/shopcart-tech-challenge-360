import bcrypt from "bcryptjs";

import type {
  RegisterInput
} from "./auth.register.schema.js";

import {
  createCustomerInDatabase
} from "./auth.register.repository.js";

export async function registerCustomer(
  input: RegisterInput
) {
  // Hash bcrypt con factor de costo 12.
  // No guardar ni registrar en logs
  // la contraseña original.
  const passwordHash = await bcrypt.hash(
    input.password,
    12
  );

  const user = await createCustomerInDatabase(
    input.correo,
    passwordHash
  );

  return {
    id: user.IDUsuario,
    correo: user.Correo,
    rol: user.NombreRol,
    fechaCreacion: new Date(
      user.FechaCreacion
    ).toISOString()
  };
}
