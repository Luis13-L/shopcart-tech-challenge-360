import bcrypt from 'bcryptjs';
import readline from 'node:readline/promises';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

const cuentas = ['Administrador', 'Operador', 'Cliente'];

try {
  console.log('Generador de hashes bcrypt para cuentas LOCALES de prueba.');
  console.log('Usa contrasenas distintas y no empleadas en cuentas reales.');
  console.log('Nota: el texto que escribas puede verse en la terminal.');

  for (const rol of cuentas) {
    const password = await rl.question(`Contrasena ${rol}: `);

    if (password.length < 12 || Buffer.byteLength(password, 'utf8') > 72) {
      throw new Error('Cada contrasena debe tener al menos 12 caracteres y no superar 72 bytes UTF-8.');
    }

    console.log(`${rol}: ${await bcrypt.hash(password, 12)}`);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
} finally {
  rl.close();
}
