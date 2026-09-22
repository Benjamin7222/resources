import { createOptions } from "./createOptions.js";

const optionsWrapper = document.getElementById("options-wrapper");
const body = document.body;
const targetingImage = document.getElementById("targetingImage");

window.addEventListener("message", (event) => {
  optionsWrapper.innerHTML = "";

  switch (event.data.event) {
    case "visible": {
      body.style.visibility = event.data.state ? "visible" : "hidden";
      // Reset to untargeted state when not visible
      if (!event.data.state) {
        targetingImage.src = "assets/untarget.png";
        targetingImage.classList.remove("has-target");
      }
      return;
    }

    case "leftTarget": {
      // Switch back to untargeted asset
      targetingImage.src = "assets/untarget.png";
      targetingImage.classList.remove("has-target");
      return;
    }

    case "setTarget": {
      // Switch to targeted asset
      targetingImage.src = "assets/target.png";
      targetingImage.classList.add("has-target");

      if (event.data.options) {
        for (const type in event.data.options) {
          event.data.options[type].forEach((data, id) => {
            createOptions(type, data, id + 1);
          });
        }
      }

      if (event.data.zones) {
        for (let i = 0; i < event.data.zones.length; i++) {
          event.data.zones[i].forEach((data, id) => {
            createOptions("zones", data, id + 1, i + 1);
          });
        }
      }
    }
  }
});