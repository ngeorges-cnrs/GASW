/* Copyright CNRS-CREATIS
 *
 * Rafael Ferreira da Silva
 * rafael.silva@creatis.insa-lyon.fr
 * http://www.rafaelsilva.com
 *
 * This software is governed by the CeCILL  license under French law and
 * abiding by the rules of distribution of free software.  You can  use,
 * modify and/ or redistribute the software under the terms of the CeCILL
 * license as circulated by CEA, CNRS and INRIA at the following URL
 * "http://www.cecill.info".
 *
 * As a counterpart to the access to the source code and  rights to copy,
 * modify and redistribute granted by the license, users are provided only
 * with a limited warranty  and the software's author,  the holder of the
 * economic rights,  and the successive licensors  have only  limited
 * liability.
 *
 * In this respect, the user's attention is drawn to the risks associated
 * with loading,  using,  modifying and/or developing or reproducing the
 * software by the user in light of its specific status of free software,
 * that may mean  that it is complicated to manipulate,  and  that  also
 * therefore means  that it is reserved for developers  and  experienced
 * professionals having in-depth computer knowledge. Users are therefore
 * encouraged to load and test the software's suitability as regards their
 * requirements in conditions enabling the security of their systems and/or
 * data to be ensured and,  more generally, to use and operate it in the
 * same conditions as regards security.
 *
 * The fact that you are presently reading this means that you have had
 * knowledge of the CeCILL license and that you accept its terms.
 */
package fr.insalyon.creatis.gasw.execution;

import fr.insalyon.creatis.gasw.GaswConfiguration;
import fr.insalyon.creatis.gasw.GaswException;
import fr.insalyon.creatis.gasw.bean.Job;
import fr.insalyon.creatis.gasw.dao.DAOException;
import fr.insalyon.creatis.gasw.dao.DAOFactory;
import fr.insalyon.creatis.gasw.dao.JobDAO;
import fr.insalyon.creatis.gasw.dao.NodeDAO;
import fr.insalyon.creatis.gasw.plugin.ListenerPlugin;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Date;
import java.util.List;

public abstract class GaswMonitor extends Thread {

    private static final Logger logger = LoggerFactory.getLogger(GaswMonitor.class);

    private volatile static int INVOCATION_ID = 1;
    protected JobDAO jobDAO;
    protected NodeDAO nodeDAO;

    protected GaswMonitor() {
        try {
            jobDAO = DAOFactory.getDAOFactory().getJobDAO();
            nodeDAO = DAOFactory.getDAOFactory().getNodeDAO();

        } catch (DAOException ex) {
            // do nothing
        }
    }

    protected synchronized void add(Job job) throws GaswException {
        try {
            // Defining invocation ID

            List<Job> list = jobDAO.getByFileName(job.getFileName());
            if (!list.isEmpty()) {
                job.setInvocationID(list.get(0).getInvocationID());
            } else {
                job.setInvocationID(INVOCATION_ID++);
            }

            job.setCreation(new Date());
            jobDAO.add(job);

            // Listeners notification
            for (ListenerPlugin listener : GaswConfiguration.getInstance().getListenerPlugins()) {
                listener.jobSubmitted(job);
            }

        } catch (DAOException ex) {
            throw new GaswException(ex);
        }
    }

    /**
     * Adds a job to be monitored. It should constructs a Job object and invoke
     * the protected method add(job).
     */
    public abstract void add(String jobID, String symbolicName, String fileName,
            String parameters) throws GaswException;

    /**
     * Updates the job status and notifies listeners.
     */
    protected void updateStatus(Job job) throws GaswException, DAOException {

        for (ListenerPlugin listener : GaswConfiguration.getInstance().getListenerPlugins()) {
            listener.jobStatusChanged(job);
        }
        jobDAO.update(job);
    }

    protected void verifySignaledJobs() {

        try {
            // Replicate jobs
            for (Job job : jobDAO.getJobs(GaswStatus.REPLICATE)) {
                replicate(job);
            }
            // Kill job replicas
            for (Job job : jobDAO.getJobs(GaswStatus.KILL_REPLICA)) {
                kill(job);
            }
            // Kill jobs
            for (Job job : jobDAO.getJobs(GaswStatus.KILL)) {
                kill(job);
            }
            // Reschedule jobs
            for (Job job : jobDAO.getJobs(GaswStatus.RESCHEDULE)) {
                reschedule(job);
            }
            // Resume held jobs
            for (Job job : jobDAO.getJobs(GaswStatus.UNHOLD_ERROR)) {
                job.setStatus(GaswStatus.ERROR);
                jobDAO.update(job);
                resume(job);
            }
            for (Job job : jobDAO.getJobs(GaswStatus.UNHOLD_STALLED)) {
                job.setStatus(GaswStatus.STALLED);
                jobDAO.update(job);
                resume(job);
            }
        } catch (DAOException ex) {
            logger.error("Error handling signaled jobs", ex);
        }
    }

    /**
     * Verifies if a job is replica and handles it in case it is.
     */
    protected boolean isReplica(Job job) throws DAOException {
        return jobDAO.getNumberOfCompletedJobsByInvocationID(job.getInvocationID()) > 0;
    }

    protected abstract void kill(Job job);
    protected abstract void reschedule(Job job);
    protected abstract void replicate(Job job);
    protected abstract void killReplicas(Job job);
    protected abstract void resume(Job job);
}
