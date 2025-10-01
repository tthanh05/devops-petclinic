package org.springframework.samples.petclinic.owner;

import org.junit.jupiter.api.Test;
import org.springframework.validation.BeanPropertyBindingResult;
import org.springframework.validation.Errors;

import static org.assertj.core.api.Assertions.assertThat;

class PetValidatorTest {

  @Test
  void rejectsEmptyName() {
    Pet pet = new Pet();
    pet.setName(""); // invalid
    Errors errors = new BeanPropertyBindingResult(pet, "pet");

    new PetValidator().validate(pet, errors);

    assertThat(errors.hasFieldErrors("name")).isTrue();
  }

  @Test
  void acceptsValidPet() {
    Pet pet = new Pet();
    pet.setName("Leo");
    Errors errors = new BeanPropertyBindingResult(pet, "pet");

    new PetValidator().validate(pet, errors);

    assertThat(errors.hasErrors()).isFalse();
  }
}
