<script>
export default {
    props: {
        title: {
            type: String,
            required: true,
        },
        description: {
            type: String,
            required: true,
        },
        color: {
            type: String,
            default: null,
        },
    },
    computed: {
        colorStyle() {
            const colors = {
                purple: {
                    50: "oklch(97% 0.015 286.1)",
                    300: "oklch(71.3% 0.158 287.5)",
                    700: "oklch(38.7% 0.222 287.7)",
                },
                pink: {
                    50: "oklch(97% 0.015 7.5)",
                    300: "oklch(73.2% 0.171 7.9)",
                    700: "oklch(40.4% 0.162 7.8)",
                },
                green: {
                    50: "oklch(97% 0.05 147)",
                    300: "oklch(77.2% 0.171 146.7)",
                    700: "oklch(43.8% 0.131 146.8)",
                },
                blue: {
                    50: "oklch(97.1% 0.014 258.3)",
                    300: "oklch(76.6% 0.12 259.5)",
                    700: "oklch(43.4% 0.172 259.4)",
                },
            };
            const color = colors[this.color] ?? colors["purple"];

            return this.color
                ? {
                      background: color[50],
                      color: color[700],
                      "border-color": color[300],
                  }
                : {};
        },
    },
};
</script>

<template>
    <div :style="colorStyle" class="card">
        <h3 class="card__title">{{ title }}</h3>
        <p class="card__description">{{ description }}</p>
    </div>
</template>

<style scoped>
.card {
    padding: 1rem;
    border-style: solid;
    border-width: 1px;
    border-radius: 0.5rem;
}
.card__title {
    margin: 0;
}
.card__description {
    margin: 0;
}
</style>
