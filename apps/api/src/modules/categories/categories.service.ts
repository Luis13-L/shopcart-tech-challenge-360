import type {
  CreateCategoryInput,
  UpdateCategoryInput
} from "./categories.schema.js";

import {
  createCategory,
  listCategories,
  updateCategory,
  changeCategoryStatus
} from "./categories.repository.js";

export const categoriesService = {

  create(
    actorId: number,
    input: CreateCategoryInput
  ) {
    return createCategory(actorId, input);
  },

  listPublic() {
    return listCategories(null, false);
  },

  listAdmin(actorId: number) {
    return listCategories(actorId, true);
  },

  update(
    actorId: number,
    categoryId: number,
    input: UpdateCategoryInput
  ) {
    return updateCategory(
      actorId,
      categoryId,
      input
    );
  },

  setActive(
    actorId: number,
    categoryId: number,
    active: boolean
  ) {
    return changeCategoryStatus(
      actorId,
      categoryId,
      active
    );
  }
};
