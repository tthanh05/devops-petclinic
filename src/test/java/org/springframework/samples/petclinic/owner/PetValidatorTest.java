package org.springframework.samples.petclinic.owner;

import org.junit.jupiter.api.Test;
import org.springframework.validation.BeanPropertyBindingResult;
import org.springframework.validation.Errors;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class PetValidatorTest {

  @Test
  void rejectsEmptyName() {
    Pet pet = new Pet();
    pet.setName(""); // invalid
    pet.setBirthDate(LocalDate.now());
    PetType type = new PetType();
    type.setName("dog");
    pet.setType(type);

    Errors errors = new BeanPropertyBindingResult(pet, "pet");

    new PetValidator().validate(pet, errors);

    // Still specifically asserts name is invalid (even if others are valid)
    assertThat(errors.hasFieldErrors("name")).isTrue();
  }

  @Test
  void acceptsValidPet() {
    Pet pet = new Pet();
    pet.setName("Leo"); // valid
    pet.setBirthDate(LocalDate.of(2020, 1, 15)); // valid
    PetType type = new PetType();
    type.setName("cat"); // valid
    pet.setType(type);

    Errors errors = new BeanPropertyBindingResult(pet, "pet");

    new PetValidator().validate(pet, errors);

    assertThat(errors.hasErrors()).isFalse();
  }
}
