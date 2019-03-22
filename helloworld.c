/* helloworld.c for TOPPERS/ATK(OSEK) */ 
#include "kernel.h"
#include "kernel_id.h"
#include "ecrobot_interface.h"

#define seuil_infra 600
#define seuil_distance 10
#define light_sensor NXT_PORT_S1
#define ultrason_sensor NXT_PORT_S2
#define choc_sensor NXT_PORT_S3
#define roue_gauche NXT_PORT_A
#define roue_droite NXT_PORT_B
#define etat_a 0
#define etat_b 1
#define etat_c 2

DeclareCounter(SysTimerCnt);
DeclareResource(sMonMDD);
DeclareResource(distanceObstacle);
DeclareResource(avanceRecule);
DeclareResource(etatChoc);
DeclareTask(Task_AcqInfra);
DeclareTask(Task_AcqUltrason);
DeclareTask(Task_AcqChoc);
DeclareTask(Task_Afficher);
DeclareTask(Task_SuivrePiste);


volatile int resourceinfra;
volatile int resourcedistance;
volatile int resourcechoc;
volatile int resourceAR;

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
	ecrobot_init_sonar_sensor(ultrason_sensor);

}




/* task ultrason pour reculer*/

TASK (Task_AcqUltrason)
{
	ecrobot_device_initialize();
	int val_ultrason;

	val_ultrason = ecrobot_get_sonar_sensor(ultrason_sensor);

	GetResource(distanceObstacle);
	GetResource(avanceRecule);

	resourcedistance = val_ultrason;

	if(val_ultrason < seuil_distance)
	{
		resourceAR = -1;
	} else {
		resourceAR = 1;
	}

	ReleaseResource(distanceObstacle);
	ReleaseResource(avanceRecule);

	TerminateTask();

}


/* task choc pour avancer*/

TASK (Task_AcqChoc)
{
	ecrobot_device_initialize();
	int val_choc;

	val_choc = ecrobot_get_touch_sensor(choc_sensor) ;

	GetResource(etatChoc);
	GetResource(avanceRecule);

	resourcechoc = val_choc;

	if(val_choc==1)
	{
		resourceAR = 1;
	}

	ReleaseResource(etatChoc);
	ReleaseResource(avanceRecule);


	TerminateTask();
}

/* task infrarouge pour suivre piste ou tourner*/

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

TASK(Task_Afficher)
{
	int val_do;
	GetResource(distanceObstacle);
	val_do = resourcedistance;

	int val_choc;
	GetResource(etatChoc);
	val_choc = resourcechoc;

	display_goto_xy(0,0);
	display_string("DO:");
	display_int(val_do,3);
	display_goto_xy(0,3);
	display_string("EC:");
	display_int(val_choc,1);

	ReleaseResource(distanceObstacle);
	ReleaseResource(etatChoc);
	TerminateTask();

}


TASK (Task_SuivrePiste)
{
	static int ar = 1;
	GetResource(avanceRecule);
	ar = resourceAR;

	int val_mdd;
	GetResource(sMonMDD);
	val_mdd = resourceinfra;

	static int etat = etat_a;
	static int capactuel;
	static int limite = 5;

	switch(etat) {
	case etat_a :/*etat original surpiste*/
		if(val_mdd > seuil_infra) { /*surpiste*/
			nxt_motor_set_speed(roue_gauche,60*ar,1);
			nxt_motor_set_speed(roue_droite,60*ar,1);
		}
		else {  /*hors piste*/
			etat = etat_b; /*tourner droite*/
			nxt_motor_set_speed(roue_gauche,60*ar,1);
			nxt_motor_set_speed(roue_droite,-60*ar,1);
			capactuel = 0;

		}

		break;

	case etat_b : /*etat original hors piste*/
		if(val_mdd > seuil_infra){	/*surpiste*/
			nxt_motor_set_speed(roue_gauche,60*ar,1);
			nxt_motor_set_speed(roue_droite,60*ar,1);
			limite = 5;
			etat= etat_a;
		} else if (capactuel > limite) {
			/*hors piste*/
			/*tourner gauche*/
			nxt_motor_set_speed(roue_gauche,-60*ar,1);
			nxt_motor_set_speed(roue_droite,60*ar,1);
			etat = etat_c;
		} else {
			capactuel = capactuel+1;
		}

		break;

	case etat_c :
		if(val_mdd > seuil_infra){	/*surpiste*/
			nxt_motor_set_speed(roue_gauche,60*ar,1);
			nxt_motor_set_speed(roue_droite,60*ar,1);
			limite = 5;
			etat = etat_a;
		} else if (capactuel < -limite) {
			/*hors piste*/
			/*tourner droite*/
			nxt_motor_set_speed(roue_gauche,60*ar,1);
			nxt_motor_set_speed(roue_droite,-60*ar,1);
			limite = limite+5;
			etat = etat_b;
		} else {
			capactuel = capactuel-1;
		}

	}

	ReleaseResource(sMonMDD);
	ReleaseResource(avanceRecule);
	TerminateTask();

}






