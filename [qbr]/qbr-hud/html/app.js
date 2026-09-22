// PLAYER HUD

const playerHud = {
    data() {
        return {
            health: 0,
            hunger: 0,
            thirst: 0,
            stress: 0,
            stamina: 0,
            voice: 0,
            temp: 0,
            show: false,
            talking: false,
            showHealth: true,
            showHunger: true,
            showThirst: true,
            showStress: true,
            showStamina: true,
            talkingColor: "#FFFFFF",
            healthColor: "#fff",
            staminaColor: "#fff",
        }
    },
    destroyed() {
        window.removeEventListener('message', this.listener);
    },
    mounted() {
        this.listener = window.addEventListener('message', (event) => {
            if (event.data.action === 'hudtick') {
                this.hudTick(event.data);
            }
        });
    },


    methods: {
        hudTick(data) {
            this.show = data.show;
            this.health = data.health;
            this.hunger = data.hunger;
            this.thirst = data.thirst;
            this.stress = data.stress;
            this.stamina = data.stamina;
            this.temp = data.temp;
            this.voice = data.voice;
            this.talking = data.talking;
            if (this.health > 100) {
                this.showHealth = true;
                this.healthColor = "#FFD700";
            } else if (this.health == 100) {
                this.showHealth = false;
            } else if (this.health <= 50) {
                this.healthColor = "#5C0000";
                this.showHealth = true;
            } else {
                this.showHealth = true;
                this.healthColor = "#fff";
            }
            if (this.hunger >= 100) {
                this.showHunger = false;
            } else {
                this.showHunger = true;
            }
            if (this.thirst >= 100) {
                this.showThirst = false;
            } else {
                this.showThirst = true;
            }
            if (this.stress <= 0) {
                this.showStress = false;
            } else {
                this.showStress = true;
            }
            if (this.stamina > 100) {
                this.staminaColor = "#FFD700";
                this.showStamina = true;
            } else if (this.stamina == 100) {
                this.showStamina = false;
            } else if (this.stamina <= 50) {
                this.showStamina = true;
                this.staminaColor = "#5C0000";
            } else {
                this.showStamina = true;
                this.staminaColor = "#FFF";
            }
			if (this.talking) {
				this.talkingColor = "#5c0000";
			} else {
				this.talkingColor = "#FFFFFF";
			}
        }
    }
}
const app = Vue.createApp(playerHud);
app.use(Quasar)
app.mount('#ui-container');
