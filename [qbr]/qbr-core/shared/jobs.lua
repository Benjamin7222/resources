QBShared = QBShared or {}
QBShared.ForceJobDefaultDutyAtLogin = true -- true: Force duty state to jobdefaultDuty | false: set duty state from database last saved
QBShared.Jobs = {
	['unemployed'] = {
		label = 'Civil',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Indépendant',
                payment = 10
            },
        },
	},
	['railroad'] = {
		label = 'train',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'train',
                payment = 10
            },
        },
	},
	['chemindefer'] = {
		label = 'Compagnie de chemin de fer',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Apprenti cheminot',
                payment = 50
            },
			['1'] = {
                name = 'Serre-frein',
                payment = 65
            },
			['2'] = {
                name = 'Chauffeur',
                payment = 80
            },
			['3'] = {
                name = 'Mécanicien',
                payment = 100
            },
			['4'] = {
                name = 'Chef de train',
                payment = 120
            },
			['5'] = {
                name = 'Directeur de la compagnie',
				isboss = true,
                payment = 150
            },
        },
	},
	['police'] = {
		label = 'Forces de l\'ordre',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Recrue',
                payment = 50
            },
			['1'] = {
                name = 'Agent',
                payment = 75
            },
			['2'] = {
                name = 'Sergent',
                payment = 100
            },
			['3'] = {
                name = 'Lieutenant',
                payment = 125
            },
			['4'] = {
                name = 'Chef',
				isboss = true,
                payment = 150
            },
        },
	},
	['ambulance'] = {
		label = 'Services médicaux',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Recrue',
                payment = 50
            },
			['1'] = {
                name = 'Ambulancier',
                payment = 75
            },
			['2'] = {
                name = 'Médecin',
                payment = 100
            },
			['3'] = {
                name = 'Chirurgien',
                payment = 125
            },
			['4'] = {
                name = 'Chef',
				isboss = true,
                payment = 150
            },
        },
	},
	['realestate'] = {
		label = 'Immobilier',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Recrue',
                payment = 50
            },
			['1'] = {
                name = 'Vente de maisons',
                payment = 75
            },
			['2'] = {
                name = 'Vente de commerces',
                payment = 100
            },
			['3'] = {
                name = 'Courtier',
                payment = 125
            },
			['4'] = {
                name = 'Directeur',
				isboss = true,
                payment = 150
            },
        },
	},
	['judge'] = {
		label = 'Honorifique',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Juge',
                payment = 100
            },
        },
	},
	['lawyer'] = {
		label = 'Cabinet d\'avocats',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Associé',
                payment = 50
            },
        },
	},
	['gouvernement'] = {
		label = 'Gouvernement',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Attaché',
                payment = 80
            },
			['1'] = {
                name = 'Secrétaire',
                payment = 120
            },
			['2'] = {
                name = 'Gouverneur',
                isboss = true,
                payment = 200
            },
        },
	},
	['journaliste_newhanover'] = {
		label = 'New Hanover Post',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Stagiaire',
                payment = 50
            },
			['1'] = {
                name = 'Journaliste',
                payment = 75
            },
			['2'] = {
                name = 'Journaliste confirmé',
                payment = 100
            },
			['3'] = {
                name = 'Rédacteur',
                payment = 125
            },
			['4'] = {
                name = 'Rédacteur en chef',
				isboss = true,
                payment = 150
            },
        },
	},
	['journaliste_newaustin'] = {
		label = 'New Austin Post',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Stagiaire',
                payment = 50
            },
			['1'] = {
                name = 'Journaliste',
                payment = 75
            },
			['2'] = {
                name = 'Journaliste confirmé',
                payment = 100
            },
			['3'] = {
                name = 'Rédacteur',
                payment = 125
            },
			['4'] = {
                name = 'Rédacteur en chef',
				isboss = true,
                payment = 150
            },
        },
	},
	['journaliste'] = {
		label = 'Journaliste',
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            ['0'] = {
                name = 'Stagiaire',
                payment = 50
            },
			['1'] = {
                name = 'Journaliste',
                payment = 75
            },
			['2'] = {
                name = 'Journaliste confirmé',
                payment = 100
            },
			['3'] = {
                name = 'Rédacteur',
                payment = 125
            },
			['4'] = {
                name = 'Rédacteur en chef',
				isboss = true,
                payment = 150
            },
        },
	}
}