/* helloworld.c for TOPPERS/ATK(OSEK) */ 
#include "kernel.h"
#include "kernel_id.h"
#include "ecrobot_interface.h"

#define seuil_infra 600
#define light_sensor NXT_PORT_S1
#define roue_gauche NXT_PORT_A
#define roue_droite NXT_PORT_B
#define etat_a 0
#define etat_b 1
#define etat_c 2

DeclareCounter(SysTimerCnt);
DeclareResource(sMonMDD);
DeclareTask(Task_AcqInfra);
DeclareTask(Task_SuivrePiste);
DeclareEvent(Reveil);

volatile int resourceinfra;

/* nxtOSEK hook to be invoked from an ISR in category 2 */

void user_1ms_isr_type2(void)
{
	StatusType ercd;

	/* Increment System Timer Count */
	ercd = SignalCounter(SysTimerCnt);
	if (ercd != E_OK)
	{
		ShutdownOS(ercd);
	}
}

void ecrobot_device_initialize(void)
{
	ecrobot_set_light_sensor_active(light_sensor);
}



TASK (Task_AcqInfra)
{
	ecrobot_device_initialize();

	int val_mdd;

	val_mdd = ecrobot_get_light_sensor(light_sensor);

	GetResource(sMonMDD);
	resourceinfra = val_mdd;
	ReleaseResource(sMonMDD);

	ChainTask(Task_SuivrePiste);

}


TASK (Task_SuivrePiste)
{

	int val_mdd;
	GetResource(sMonMDD);
	val_mdd = resourceinfra;

	static int etat = etat_a;
	static int capactuel;
	static int limite = 5;

	switch(etat) {
	case etat_a :/*etat original surpiste*/
		if(val_mdd > seuil_infra) { /*surpiste*/
			nxt_motor_set_speed(roue_gauche,60,1);
			nxt_motor_set_speed(roue_droite,60,1);
		}
		else {  /*hors piste*/
			etat = etat_b; /*tourner droite*/
			nxt_motor_set_speed(roue_gauche,60,1);
			nxt_motor_set_speed(roue_droite,-60,1);
			capactuel = 0;

		}

		break;

	case etat_b : /*etat original hors piste*/
		if(val_mdd > seuil_infra){	/*surpiste*/
			nxt_motor_set_speed(roue_gauche,60,1);
			nxt_motor_set_speed(roue_droite,60,1);
			limite = 5;
			etat= etat_a;
		} else if (capactuel > limite) {
			/*hors piste*/
			/*tourner gauche*/
			nxt_motor_set_speed(roue_gauche,-60,1);
			nxt_motor_set_speed(roue_droite,60,1);
			etat = etat_c;
		} else {
			capactuel = capactuel+1;
		}

		break;

	case etat_c :
		if(val_mdd > seuil_infra){	/*surpiste*/
			nxt_motor_set_speed(roue_gauche,60,1);
			nxt_motor_set_speed(roue_droite,60,1);
			limite = 5;
			etat = etat_a;
		} else if (capactuel < -limite) {
			/*hors piste*/
			/*tourner droite*/
			nxt_motor_set_speed(roue_gauche,60,1);
			nxt_motor_set_speed(roue_droite,-60,1);
			limite = limite+5;
			etat = etat_b;
		} else {
			capactuel = capactuel-1;
		}

	}

	ReleaseResource(sMonMDD);

	TerminateTask();

}



