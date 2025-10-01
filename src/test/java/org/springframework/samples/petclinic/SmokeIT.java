package org.springframework.samples.petclinic;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SmokeIT {

  @LocalServerPort
  int port;

  @Autowired
  private TestRestTemplate rest;

  @Test
  void healthIsUp() {
    ResponseEntity<String> r = rest.getForEntity("/actuator/health", String.class);
    assertThat(r.getStatusCode().is2xxSuccessful()).isTrue();
    assertThat(r.getBody()).contains("UP");
  }

  @Test
  void homePageLoads() {
    ResponseEntity<String> r = rest.getForEntity("/", String.class);
    assertThat(r.getStatusCode().is2xxSuccessful()).isTrue();
    assertThat(r.getBody()).containsIgnoringCase("petclinic");
  }
}
