package org.springframework.samples.petclinic.owner;

import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

class OwnerServiceTest {

  @Test
  void findOwnerReturnsOwnerWhenExists() {
    OwnerRepository repo = Mockito.mock(OwnerRepository.class);
    Owner expected = new Owner();
    expected.setFirstName("George");
    expected.setLastName("Franklin");
    when(repo.findById(1)).thenReturn(Optional.of(expected));

    OwnerService service = new OwnerService(repo);
    Optional<Owner> result = service.findOwner(1);

    assertThat(result).isPresent();
    assertThat(result.get().getFirstName()).isEqualTo("George");
  }
}
